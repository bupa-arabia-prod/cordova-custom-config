const fs = require('fs');
const path = require('path');

module.exports = function (context) {
    console.log('[ForceLocalize] === Injecting Localizations & Overriding Info.plist ===');

    const projectRoot = context.opts.projectRoot;
    const iosRoot = path.join(projectRoot, 'platforms', 'ios');

    if (!fs.existsSync(iosRoot)) {
        console.warn('[ForceLocalize] platforms/ios not found. Skipping.');
        return;
    }

    // 1. Define localized strings for the ATT permission dialog
    const localizationContent = {
        'ar': '/* Arabic ATT Permission */\n"NSUserTrackingUsageDescription" = "سيتم استخدام بياناتك لتقديم خدمات مخصصة وتحسين تجربة التطبيق.";\n',
        'en': '/* English ATT Permission */\n"NSUserTrackingUsageDescription" = "Your data will be used to deliver personalized services and enhance your app experience.";\n'
    };

    // 2. Locate all target .app folders and the main project folder
    function findTargetAppDirs(dir) {
        let results = [];
        const list = fs.readdirSync(dir, { withFileTypes: true });
        list.forEach(item => {
            const fullPath = path.join(dir, item.name);
            if (item.isDirectory()) {
                if (item.name.endsWith('.app') || fs.existsSync(path.join(fullPath, `${item.name}-Info.plist`))) {
                    results.push(fullPath);
                } else if (item.name === 'build' || item.name === 'DerivedData') {
                    results = results.concat(findTargetAppDirs(fullPath));
                }
            }
        });
        return results;
    }

    const targetDirs = findTargetAppDirs(iosRoot);
    console.log(`[ForceLocalize] Target directories found: ${JSON.stringify(targetDirs)}`);

    // 3. Inject ar.lproj and en.lproj folders + InfoPlist.strings into all target directories
    targetDirs.forEach(targetDir => {
        ['ar', 'en'].forEach(lang => {
            const lprojDir = path.join(targetDir, `${lang}.lproj`);
            if (!fs.existsSync(lprojDir)) {
                fs.mkdirSync(lprojDir, { recursive: true });
                console.log(`[ForceLocalize] Created directory: ${lprojDir}`);
            }

            const stringsFile = path.join(lprojDir, 'InfoPlist.strings');
            fs.writeFileSync(stringsFile, localizationContent[lang], 'utf8');
            console.log(`[ForceLocalize] Injected InfoPlist.strings into: ${stringsFile}`);
        });

        // 4. Overwrite CFBundleLocalizations in any Info.plist found in these directories
        const plistFiles = fs.readdirSync(targetDir).filter(f => f.endsWith('-Info.plist') || f === 'Info.plist');
        plistFiles.forEach(plistName => {
            const plistPath = path.join(targetDir, plistName);
            try {
                let content = fs.readFileSync(plistPath, 'utf8');
                const regex = /<key>CFBundleLocalizations<\/key>[\s\S]*?<\/array>/;
                const replacement = `<key>CFBundleLocalizations</key>\n\t<array>\n\t\t<string>en</string>\n\t\t<string>ar</string>\n\t</array>`;

                if (regex.test(content)) {
                    content = content.replace(regex, replacement);
                } else {
                    content = content.replace('</dict>', `\t${replacement}\n</dict>`);
                }

                fs.writeFileSync(plistPath, content, 'utf8');
                console.log(`[ForceLocalize] Overwrote CFBundleLocalizations in: ${plistPath}`);
            } catch (err) {
                console.error(`[ForceLocalize] Failed to update ${plistPath}: ${err.message}`);
            }
        });
    });
};
