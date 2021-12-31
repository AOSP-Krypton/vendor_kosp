package generator

import (
	"fmt"

	"android/soong/android"
)

func kryptonExpandVariables(ctx android.ModuleContext, in string) string {
	kryptonVars := ctx.Config().VendorConfig("kryptonVarsPlugin")

	out, err := android.Expand(in, func(name string) (string, error) {
		if kryptonVars.IsSet(name) {
			return kryptonVars.String(name), nil
		}
		// This variable is not for us, restore what the original
		// variable string will have looked like for an Expand
		// that comes later.
		return fmt.Sprintf("$(%s)", name), nil
	})

	if err != nil {
		ctx.PropertyErrorf("%s: %s", in, err.Error())
		return ""
	}

	return out
}