#!/usr/bin/env kotlin

/**
 * A kt script to sync different apn configuration XML files
 */

@file:Import("util.main.kts")

import java.io.File
import java.io.FileOutputStream

import javax.xml.parsers.DocumentBuilderFactory
import javax.xml.transform.OutputKeys
import javax.xml.transform.TransformerFactory
import javax.xml.transform.dom.DOMSource
import javax.xml.transform.stream.StreamResult
import javax.xml.transform.stream.StreamSource

import kotlin.system.exitProcess

import org.w3c.dom.Document
import org.w3c.dom.Element
import org.w3c.dom.Node
import org.w3c.dom.NodeList

private val apnsToMerge = mutableListOf<File>()
private lateinit var outputFile: File

// Script starts here
parseOptions()
syncApns()

/**
 * Parse required options
 */
fun parseOptions() {
    if (args.contains(Args.HELP)) {
        help()
        exitProcess(0)
    }
    Utils.getArgValues(Args.APNS, args).forEach {
        val file = File(it)
        if (!file.isFile) {
            Log.error("File ${file.absolutePath} does not exist")
            exitProcess(1)
        }
        apnsToMerge.add(file)
    }
    outputFile = File(Utils.getArgValue(Args.OUTPUT, args))
    if (outputFile.isFile) {
        val input = Utils.inputPrompt(
            prompt = "Output file ${outputFile.absolutePath} exists, overwrite (y/N)?",
            inputFilter = listOf("y", "Y", "n", "N"),
            defaultOnEnter = true
        )
        if (input != "y" && input != "Y") {
            Log.info("Aborting apns sync")
            exitProcess(0)
        }
    }
}

/**
 * Print help message
 */
fun help() {
    println("Script to merge different apns-conf without duplicating carrier APNs\n" +
            "Usage: ./sync_apns.main.kts -apns apns-conf1.xml apns-conf2.xml ... -output merged-apns-conf.xml"
    )
}

/**
 * Syncs apns from files in [apnsToMerge]. Uses the first file
 * as the merged xml document base and then adds all nodes (including comments)
 * from other files.
 */
fun syncApns() {
    val docBuilder = DocumentBuilderFactory.newInstance().newDocumentBuilder()
    // Parse and use the first xml doc as the parent for merging others into
    val mergeDoc = docBuilder.parse(apnsToMerge.first())
    val mergeDocElement = mergeDoc.documentElement
    val mergeVersion = mergeDocElement.getAttribute(ApnAttr.VERSION).toInt()
    // To store carrier name of the merged apns so that we don't have
    // to loop through all the elements of current merged doc
    val mergedApns = mutableListOf<Node>()
    loadInitialList(mergeDoc.getElementsByTagName(ApnAttr.APN), mergedApns)

    for (i in 1 until apnsToMerge.size) {
        val doc: Document = docBuilder.parse(apnsToMerge[i])
        val rootElement = doc.documentElement
        val version = rootElement.getAttribute(ApnAttr.VERSION).toInt()
        if (version != mergeVersion) {
            Log.warn("Apn version $version is not the same as merge version $mergeVersion")
            continue
        }
        val childNodes = rootElement.childNodes // Including comments
        for (j in 0 until childNodes.length) {
            val node: Node = childNodes.item(j)
            when (node.nodeType) {
                Node.ELEMENT_NODE -> {
                    val element = (node as Element)
                    if (!mergedApns.any { it.isEqualNode(node) }) {
                        val importedNode = mergeDoc.importNode(node, true)
                        mergeDocElement.appendChild(importedNode)
                        mergedApns.add(node)
                    }
                }
                Node.COMMENT_NODE -> {
                    val importedNode = mergeDoc.importNode(node, true)
                    mergeDocElement.appendChild(importedNode)
                }
                else -> continue
            }
        }
    }
    saveMergedDoc(mergeDoc)
}

/**
 * Adds all the apn carrier names to @param mergedApns so that for further
 * merge these apns can be excluded.
 */
fun loadInitialList(apnsNodeList: NodeList, mergedApns: MutableList<Node>) {
    for (i in 0 until apnsNodeList.length) {
        val node: Node = apnsNodeList.item(i)
        if (node.nodeType != Node.ELEMENT_NODE) continue
        if (!mergedApns.any { it.isEqualNode(node) }) {
            mergedApns.add(node)
        }
    }
}

/**
 * Saved the merged doc to [outputFile] file
 */
fun saveMergedDoc(mergedDoc: Document) {
    val transformer = TransformerFactory.newInstance().newTransformer(
        StreamSource(File(Constants.APN_FORMAT))
    ).apply {
        setOutputProperty(OutputKeys.INDENT, "yes")
    }
    val domSource = DOMSource(mergedDoc)
    FileOutputStream(outputFile).use {
        transformer.transform(domSource, StreamResult(it))
        it.flush()
    }
}

object Args {
    const val HELP = "-help"
    const val APNS = "-apns"
    const val OUTPUT = "-output"
}

object ApnAttr {
    const val VERSION = "version"
    const val APN = "apn"
    const val CARRIER = "carrier"
}

object Constants {
    const val APN_FORMAT = "vendor/krypton/scripts/apn-format.xslt"
}
