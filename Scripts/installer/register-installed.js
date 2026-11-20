// Invoked as the console user. Only retire copies created by past MouseEasy
// build or installer layouts. Other user installations keep their registration.
ObjC.import("AppKit");
function run() {
    const id = "io.github.yyfan.MouseWorkbench.dev";
    const installed = "/Applications/MouseEasy.app";
    const registrar = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";
    const bundleID = path => {
        const bundle = $.NSBundle.bundleWithPath(path);
        return !bundle.isNil() && ObjC.unwrap(bundle.bundleIdentifier) === id;
    };
    if (!bundleID(installed)) return;
    function register(flag, path) {
        const task = $.NSTask.alloc.init;
        task.launchPath = registrar;
        task.arguments = [flag, path];
        task.launch;
        task.waitUntilExit;
        return task.terminationStatus === 0;
    }
    const paths = $.NSWorkspace.sharedWorkspace.URLsForApplicationsWithBundleIdentifier(id);
    const oldBuild = /\/build\/(?:MouseEasy\.app|candidates\/[^/]+\/MouseEasy\.app|local\/(?:products\.noindex\/MouseEasy\.app|archives\.noindex\/[^/]+\.app\.saved))$/;
    const oldImage = /^\/Volumes\/MouseEasy [\d.]+(?: \d+)?\/MouseEasy\.app$/;
    for (let i = 0; i < paths.count; i++) {
        const path = ObjC.unwrap(paths.objectAtIndex(i).path);
        if ((oldBuild.test(path) || oldImage.test(path)) && bundleID(path))
            register("-u", path);
    }
    if (!register("-f", installed)) throw Error("Could not register installed MouseEasy");
}
