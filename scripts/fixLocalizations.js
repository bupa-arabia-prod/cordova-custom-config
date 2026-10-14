const fs = require('fs');
const path = require('path');

module.exports = function (context) {
    console.log('[ForceLocalize] === Injecting Localizations into App Bundle ===');

    const projectRoot = context.opts.projectRoot;
    const iosRoot = path.join(projectRoot, 'platforms', 'ios');

    if (!fs.existsSync(iosRoot)) {
        console.warn('[ForceLocalize] platforms/ios not found. Skipping.');
        return;
    }

    // Exact localized descriptions for the ATT permission dialog
    const localizationContent = {
        'ar': '/* Arabic ATT Permission */\n"NSUserTrackingUsageDescription" = "سيتم استخدام بياناتك لتقديم خدمات مخصصة وتحسين تجربة التطبيق.";\n',
        'en': '/* English ATT Permission */\n"NSUserTrackingUsageDescription" = "Your data will be used to deliver personalized services and enhance your app experience.";\n'
    };

    // Recursively locate all destination directories:
    // 1. Any directory ending in .app (e.g. inside .xcarchive or build outputs)
    // 2. The project directory containing *-Info.plist
    function findTargetAppDirs(dir) {
        let results = [];
        try {
            const list = fs.readdirSync(dir, { withFileTypes: true });
            for (const item of list) {
                const fullPath = path.join(dir, item.name);
                if (item.isDirectory()) {
                    if (item.name.endsWith('.app')) {
                        results.push(fullPath);
                    } else if (fs.existsSync(path.join(fullPath, `${item.name}-Info.plist`))) {
                        results.push(fullPath);
                    }
                    
                    // Traverse build directories, Xcode archives, and derived products
                    if (
                        ['build', 'DerivedData', 'InstallationBuildProductsLocation', 'Applications', 'Products'].includes(item.name) ||
                        item.name.endsWith('.xcarchive')
                    ) {
                        results = results.concat(findTargetAppDirs(fullPath));
                    }
                }
            }
        } catch (e) {
            console.warn(`[ForceLocalize] Error scanning ${dir}: ${e.message}`);
        }
        return results;
    }

    // 1. Scan platforms/ios
    let targetDirs = findTargetAppDirs(iosRoot);

    // 2. Check Xcode's global DerivedData path if available in environment
    const homeDir = process.env.HOME || '';
    if (homeDir) {
        const derivedDataDir = path.join(homeDir, 'Library/Developer/Xcode/DerivedData');
        if (fs.existsSync(derivedDataDir)) {
            targetDirs = targetDirs.concat(findTargetAppDirs(derivedDataDir));
        }
    }

    // Deduplicate discovered paths
    targetDirs = Array.from(new Set(targetDirs));
    console.log(`[ForceLocalize] Target directories found: ${JSON.stringify(targetDirs)}`);

    targetDirs.forEach(targetDir => {
        // A. Inject ar.lproj and en.lproj folders + InfoPlist.strings
        ['ar', 'en'].forEach(lang => {
            const lprojDir = path.join(targetDir, `${lang}.lproj`);
            if (!fs.existsSync(lprojDir)) {
                fs.mkdirSync(lprojDir, { recursive: true });
                console.log(`[ForceLocalize] Created: ${lprojDir}`);
            }

            const stringsFile = path.join(lprojDir, 'InfoPlist.strings');
            fs.writeFileSync(stringsFile, localizationContent[lang], 'utf8');
            console.log(`[ForceLocalize] Injected InfoPlist.strings -> ${stringsFile}`);
        });

        // B. Enforce CFBundleLocalizations [en, ar] in any Info.plist in the directory
        try {
            const plistFiles = fs.readdirSync(targetDir).filter(f => f.endsWith('-Info.plist') || f === 'Info.plist');
            plistFiles.forEach(plistName => {
                const plistPath = path.join(targetDir, plistName);
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
            });
        } catch (err) {
            console.error(`[ForceLocalize] Error updating plist in ${targetDir}: ${err.message}`);
        }
    });
};
