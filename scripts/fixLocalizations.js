const fs = require('fs');
const path = require('path');

module.exports = function (context) {
    const projectRoot = context.opts.projectRoot;
    const iosPlatformPath = path.join(projectRoot, 'platforms', 'ios');

    if (!fs.existsSync(iosPlatformPath)) {
        return;
    }

    // Try finding Cordova's bundled plist parser first
    let plist;
    try {
        plist = context.requireCordovaModule('plist');
    } catch (e) {
        try {
            plist = require('plist');
        } catch (err) {
            plist = null;
        }
    }

    // Locate the app's Info.plist
    const entries = fs.readdirSync(iosPlatformPath, { withFileTypes: true });
    const projectDir = entries.find(entry => 
        entry.isDirectory() && 
        fs.existsSync(path.join(iosPlatformPath, entry.name, `${entry.name}-Info.plist`))
    );

    if (!projectDir) {
        console.warn('[LocalizationHook] App directory with Info.plist not found.');
        return;
    }

    const plistPath = path.join(iosPlatformPath, projectDir.name, `${projectDir.name}-Info.plist`);

    if (fs.existsSync(plistPath)) {
        let content = fs.readFileSync(plistPath, 'utf8');

        if (plist) {
            const parsed = plist.parse(content);
            parsed.CFBundleLocalizations = ['en', 'ar'];
            fs.writeFileSync(plistPath, plist.build(parsed), 'utf8');
            console.log('[LocalizationHook] Successfully set CFBundleLocalizations via plist parser.');
        } else {
            // Safe fallback without external libraries
            const regex = /<key>CFBundleLocalizations<\/key>[\s\S]*?<\/array>/;
            const replacement = `<key>CFBundleLocalizations</key>\n\t<array>\n\t\t<string>en</string>\n\t\t<string>ar</string>\n\t</array>`;

            if (regex.test(content)) {
                content = content.replace(regex, replacement);
            } else {
                content = content.replace('</dict>', `\t${replacement}\n</dict>`);
            }
            fs.writeFileSync(plistPath, content, 'utf8');
            console.log('[LocalizationHook] Successfully set CFBundleLocalizations via XML replacement.');
        }
    }
};