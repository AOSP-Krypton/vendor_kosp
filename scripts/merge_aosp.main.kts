#!/usr/bin/env kotlin

/**
 * A kt script to merge aosp tag in repositories specified
 * in a manifest XML.
 */

@file:Repository("https://repo.maven.apache.org/maven2/")
@file:DependsOn("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.3.2")

import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.TimeUnit

import javax.xml.parsers.DocumentBuilderFactory

import kotlin.system.exitProcess

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex

import org.w3c.dom.Document
import org.w3c.dom.Element
import org.w3c.dom.Node

// Manifest xml to get repositories for merging aosp
private val manifest = File("${ManifestAttrs.MANIFEST_REPO_PATH}/snippets/krypton.xml")
private val excludeFile = File(Constants.MERGE_EXCLUDE_FILE)

private val savedStateMap = mutableMapOf<String, SavedState>()

private val mutex = Mutex()

// AOSP tag to merge
private lateinit var tag: String

// Whether to push after merging tag
private var push = false

// Whether to bump version after successfully merging
private var bump = false

// Whether to continue merging from the last saved state
private var continueMerge = false

// Process starts here
parseOptions()
if (continueMerge) parseSavedState()
merge()

/**
 * Prints help message for krypton_help function from envsetup
 */
fun help() {
    println(
        "- merge_aosp: Fetch and merge the given tag from aosp source for the repos forked from aosp in krypton.xml\n" +
                "      Usage: merge_aosp [-t] <tag> [-p] [-b]\n" +
                "             -t for aosp tag to merge\n" +
                "             -p to push to github for all repos\n" +
                "             -b to bump current minor version\n" +
                "             -c to continue merge from the last saved state\n" +
                "             -h to print this message\n" +
                "      Example: merge_aosp -t android-12.0.0_r2 -p"
    )
}

/**
 * Parse command line options from [args] and store them in variables
 */
fun parseOptions() {
    if (args.contains(Args.HELP)) {
        help()
        exitProcess(0)
    }
    // Parse tag
    if (!args.contains(Args.TAG)) {
        Log.fatal("tag [ ${Args.TAG} option ] is not specified!")
        exitProcess(1)
    }
    tag = getArgValue(Args.TAG)
    push = args.contains(Args.PUSH)
    bump = args.contains(Args.BUMP)
    continueMerge = args.contains(Args.CONTINUE)
}

/**
 * Attempts to get a value for an arg by getting the
 * value at next index in [args]. Exits if unable to get
 * argument. Call this function only if a value is supposed
 * to be passed along with the arg.
 */
fun getArgValue(arg: String): String {
    val index = args.indexOf(arg)
    if (args.size == (index + 1)) {
        Log.fatal("argument $arg does not have any supplied value")
        exitProcess(1)
    }
    return args[index + 1]
}

/**
 * Reads the [Constants.SAVED_STATE_FILE] file and maps
 * project path to it's state.
 */
fun parseSavedState() {
    val savedStateFile = File(Constants.SAVED_STATE_FILE)
    if (!savedStateFile.isFile) {
        Log.warn("Saved state file is missing, merge will start fresh")
        return
    }
    try {
        FileInputStream(savedStateFile).bufferedReader().use {
            it.readText()
        }.split("\n").forEach {
            val path = it.substringBefore(";")
            savedStateMap[path] = parseStateFromString(it)
        }
    } catch (e: IOException) {
        Log.error("Failed to read saved state file!")
        exitProcess(0)
    }
}

/**
 * Un-flattens a [SavedState] object flattened with
 * it's [SavedState.toString] function
 */
fun parseStateFromString(line: String): SavedState {
    val separatedVars = line.split(";")
    return SavedState(
        separatedVars[1].substringAfter("=").toBoolean(),
        separatedVars[2].substringAfter("=").toBoolean()
    )
}

/**
 * An overloaded version of the function below where @param cmd is a single command to run
 * which will be split into a list based on \\s (whitespace).
 */
fun run(cmd: String, dir: String? = null, timeout: Long = Constants.PROC_TIMEOUT): Output {
    return run(cmd.split("\\s".toRegex()), dir, timeout)
}

/**
 * Wrapper function to run a shell command
 *
 * @param commands the list of commands to pass to the [ProcessBuilder] constructor
 * @param dir the working directory in which this command should be run
 * @param timeout time in millis to wait until the process should be killed.
 *                Defaults to 10 minutes.
 *
 * @return an [Output] which contains the exit status of the command and output / error message as well
 */
fun run(commands: List<String>, dir: String? = null, timeout: Long = Constants.PROC_TIMEOUT): Output {
    try {
        val process = ProcessBuilder(commands)
            .redirectOutput(ProcessBuilder.Redirect.PIPE)
            .redirectError(ProcessBuilder.Redirect.PIPE).also {
                if (dir != null) it.directory(File(dir))
            }.start().also {
                it.waitFor(timeout, TimeUnit.MILLISECONDS)
            }
        return Output(
            process.exitValue(),
            process.inputStream.bufferedReader().use { it.readText() },
            process.errorStream.bufferedReader().use { it.readText() },
        )
    } catch (e: IOException) {
        Log.fatal("${e.message}")
        exitProcess(1)
    }
}

/**
 * Fetches project list parsed from [manifest], excluding the
 * one's returned from [getExcludeList], and then sequentially
 * fetches and merges AOSP tag.
 */
fun merge() {
    // Delete any saved state
    if (!continueMerge) File(Constants.SAVED_STATE_FILE).delete()
    Log.info("Kicking off merge with tag $tag")
    // Merge in all repositories
    val cores = Runtime.getRuntime().availableProcessors()
    var projectMap = getProjectMap(getExcludeList()).filter {
        run("git -C ${it.key} rev-parse").exitCode == 0
    }
    if (continueMerge) {
        projectMap = projectMap.filterNot { savedStateMap[it.key]?.shouldSkip() == true }
    }
    runBlocking(Dispatchers.Default) {
        projectMap.entries.chunked(cores).forEach {
            launch {
                mergeInternal(it)
            }
        }
    }
    if (savedStateMap.isNotEmpty()) saveStateMapToFile()
    // Merge in manifest
    fetchAndMerge(ManifestAttrs.MANIFEST_REPO_PATH, ManifestAttrs.MANIFEST_REPO_NAME)
    if (push) pushToGit(ManifestAttrs.MANIFEST_REPO_PATH, ManifestAttrs.MANIFEST_REPO_NAME)
    // Bump version and push if specified
    if (bump) {
        bumpVersion()
        if (push) pushToGit(Constants.VENDOR_PATH, Constants.VENDOR_REPO)
    }
}

/**
 * Internal function to merge tag in subprojects
 *
 * @param projects the list of subprojects
 */
suspend fun mergeInternal(projects: List<Map.Entry<String, String>>) {
    projects.forEach {
        // Check if we should merge
        if (savedStateMap[it.key]?.merged != true) {
            // build/make repo is platform/build in aosp, so we need to pass in separate
            // path and repo name
            val success = if (it.key == ManifestAttrs.BUILD_REPO_PATH) {
                fetchAndMerge(it.key, ManifestAttrs.BUILD_REPO_NAME)
            } else {
                fetchAndMerge(it.key)
            }
            if (success) updateStateLocked(it.key, merged = true, pushed = false)
        }
        // There is no need to check for saved state here since repos
        // that have already been merged and pushed are filtered out of
        // project list in the beginning
        if (push && pushToGit(it.key, it.value)) {
            updateStateLocked(it.key, merged = true, pushed = true)
        }
    }
}

/**
 * Updates [savedStateMap] under a mutex lock
 *
 * @param path the path of the repository
 * @param merged whether merge was done in this repo
 * @param pushed whether repo was pushed to remote git repository
 */
suspend fun updateStateLocked(path: String, merged: Boolean, pushed: Boolean) {
    mutex.lock()
    savedStateMap[path] = SavedState(merged, pushed)
    mutex.unlock()
}

/**
 * Flattens each element of the [savedStateMap] to a string
 * of the format path;merged=boolean;pushed=boolean, and then saves
 * it to the [Constants.SAVED_STATE_FILE] file
 */
fun saveStateMapToFile() {
    val stateFile = File(Constants.SAVED_STATE_FILE)
    try {
        FileOutputStream(stateFile).use {
            savedStateMap.forEach { (path, state) ->
                it.write("$path;$state\n".toByteArray())
            }
            it.flush()
        }
    } catch (e: IOException) {
        Log.error("Failed to save state, ${e.message}")
    }
}

/**
 * Returns a list of projects to be excluded from merging AOSP
 * tag. List is parsed from [excludeFile].
 */
fun getExcludeList(): List<String> {
    if (!excludeFile.isFile) return emptyList()
    val list: List<String>
    try {
        list = FileInputStream(excludeFile).bufferedReader().use {
            it.readText()
        }.split("\n").filter { it.isNotBlank() }
    } catch (e: IOException) {
        Log.fatal("IOException while parsing exclude list, ${e.message}")
        exitProcess(1)
    }
    return list
}

/**
 * Returns a map of project path to it's name, parsed from [manifest].
 *
 * @param exclude [List] of project paths to exclude from the parsed list.
 */
fun getProjectMap(exclude: List<String>): Map<String, String> {
    val map = mutableMapOf<String, String>()
    try {
        val factory = DocumentBuilderFactory.newInstance()
        val docBuilder = factory.newDocumentBuilder()
        val doc: Document = docBuilder.parse(manifest)
        val projectNodeList = doc.getElementsByTagName(ManifestAttrs.PROJECT)
        for (i in 0 until projectNodeList.length) {
            val node: Node = projectNodeList.item(i)
            if (node.nodeType != Node.ELEMENT_NODE) continue
            val element = (node as Element)
            val path = element.getAttribute(ManifestAttrs.PATH)
            if (!exclude.contains(path)) {
                map[path] = element.getAttribute(ManifestAttrs.NAME)
            }
        }
        return map
    } catch (e: Exception) {
        Log.fatal(e.message)
        exitProcess(1)
    }
}

/**
 * Actual function that fetches and then merges AOSP tag.
 *
 * @param path the path of the repository in which the tag should be merged
 * @param name the name of the repository to fetch from. Should be whatever that
 * comes after [ManifestAttrs.PLATFORM_URL] for this repo's url
 */
fun fetchAndMerge(path: String, name: String = path): Boolean {
    val url = "${ManifestAttrs.PLATFORM_URL}/$name"
    val fetchOut = run("git fetch $url $tag", path)
    if (fetchOut.exitCode != 0) {
        Log.error("Fetching tag for $path failed, reason: ${fetchOut.error}")
        return false
    }
    val mergeOut = run("git merge FETCH_HEAD", path)
    if (mergeOut.exitCode != 0) {
        Log.error("Merge failed for $path, reason: ${mergeOut.error}")
        return false
    }
    Log.info("Merged in $path")
    return true
}

/**
 * Push current HEAD to remote repository
 *
 * @param path path of git repo to push
 * @param name name of the git repo as given in the organization
 */
fun pushToGit(path: String, name: String): Boolean {
    val pushOut = run(
        "git push ${Constants.REMOTE_BASE_URL}/$name" +
                " HEAD:${Constants.REMOTE_BRANCH}", path
    )
    if (pushOut.exitCode != 0) {
        Log.error("Failed to push $path, reason: ${pushOut.error}")
        return false
    }
    Log.info("Pushed $path successfully!")
    return true
}

/**
 * Bumps minor version (KRYPTON_VERSION_MINOR) by 1 in file [Constants.PROP_FILE]
 */
fun bumpVersion() {
    val propFile = File(Constants.PROP_FILE)
    if (!propFile.isFile) {
        Log.fatal("${Constants.PROP_FILE} is non-existent, bumping version unsuccessful")
        exitProcess(1)
    }

    // Parse file and props
    var fileString: String
    val majorVersionString: String
    val minorVersionString: String
    try {
        fileString = FileInputStream(propFile).bufferedReader().use { it.readText() }
        majorVersionString = fileString.split("\n").first { it.contains(Constants.MAJOR_VERSION_STRING_PATTERN) }
        minorVersionString = fileString.split("\n").first { it.contains(Constants.MINOR_VERSION_STRING_PATTERN) }
    } catch (e: IOException) {
        Log.fatal("Failed to fully read ${Constants.PROP_FILE}, ${e.message}")
        exitProcess(1)
    }
    if (minorVersionString.isBlank() || majorVersionString.isBlank()) {
        Log.fatal("Unable to get current version")
        exitProcess(1)
    }

    val majorVersion = majorVersionString.substringAfter(":= ").toInt()
    val currentMinorVersion = minorVersionString.substringAfter(":= ").toInt()
    val newMinorVersion = currentMinorVersion + 1
    val newVersionString = "${Constants.MINOR_VERSION_STRING_PATTERN} $newMinorVersion"
    // Replace prop
    fileString = fileString.replace(minorVersionString, newVersionString)
    // Write to file
    Log.info("Bumping version from $majorVersion.$currentMinorVersion to $majorVersion.$newMinorVersion")
    try {
        FileOutputStream(propFile).bufferedWriter().use {
            it.write(fileString)
            it.flush()
        }
    } catch (e: IOException) {
        Log.fatal("Failed to rewrite ${Constants.PROP_FILE}, ${e.message}")
        exitProcess(1)
    }
    // Commit changes
    val propFileRelativePath = Constants.PROP_FILE.substringAfter("${Constants.VENDOR_PATH}/")
    run("git add $propFileRelativePath", Constants.VENDOR_PATH)
    run(
        listOf("git", "commit", "-m", "krypton: bump version to $majorVersion.$newMinorVersion"),
        Constants.VENDOR_PATH
    )
    Log.info("Successfully saved file!")
}

/**
 * A data class representing the state of a current repository
 */
class SavedState(
    val merged: Boolean,
    private val pushed: Boolean,
) {
    /**
     * Whether this repository should be excluded from projects to merge list
     */
    fun shouldSkip() = merged && pushed

    override fun toString(): String = "merged=$merged;pushed=$pushed"
}

/**
 * A data class representing the output of a process
 */
data class Output(
    val exitCode: Int,
    val output: String?,
    val error: String?
)

/**
 * Utility object for logging messages to console
 */
object Log {
    fun info(msg: String?) {
        println("Info: $msg")
    }

    fun warn(msg: String?) {
        println("Warning: $msg")
    }

    fun error(msg: String?) {
        println("Error: $msg")
    }

    fun fatal(msg: String?) {
        println("Fatal error: $msg")
    }
}

/**
 * Supported command line arguments
 */
object Args {
    const val TAG = "-t"
    const val BUMP = "-b"
    const val PUSH = "-p"
    const val CONTINUE = "-c"
    const val HELP = "-h"
}

object ManifestAttrs {
    const val PLATFORM_URL = "https://android.googlesource.com/platform"
    const val PROJECT = "project"
    const val PATH = "path"
    const val NAME = "name"

    const val BUILD_REPO_NAME = "build"
    const val BUILD_REPO_PATH = "build/make"

    const val MANIFEST_REPO_NAME = "manifest"
    const val MANIFEST_REPO_PATH = ".repo/manifests"
}

object Constants {
    val PROC_TIMEOUT = TimeUnit.MINUTES.toMillis(10)

    const val REMOTE_BASE_URL = "git@github.com:AOSP-Krypton"
    const val REMOTE_BRANCH = "A12"

    const val VENDOR_PATH = "vendor/krypton"
    const val VENDOR_REPO = "vendor_krypton"

    const val PROP_FILE = "$VENDOR_PATH/config/version.mk"
    const val MAJOR_VERSION_STRING_PATTERN = "KRYPTON_VERSION_MAJOR :="
    const val MINOR_VERSION_STRING_PATTERN = "KRYPTON_VERSION_MINOR :="

    const val MERGE_EXCLUDE_FILE = "$VENDOR_PATH/scripts/aosp_merge_exclude.txt"
    const val SAVED_STATE_FILE = "$VENDOR_PATH/scripts/saved_state.txt"
}