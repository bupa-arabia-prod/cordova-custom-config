const fs = require('fs');
const path = require('path');

module.exports = function (context) {
    const projectRoot = context.opts.projectRoot;
    const iosPlatformPath = path.join(projectRoot, 'platforms', 'ios');

    if (!fs.existsSync(iosPlatformPath)) {
        return;
    }

    // 1. Locate the app directory inside platforms/ios
    const entries = fs.readdirSync(iosPlatformPath, { withFileTypes: true });
    const projectDir = entries.find(entry =>
        entry.isDirectory() &&
        fs.existsSync(path.join(iosPlatformPath, entry.name, `${entry.name}-Info.plist`))
    );

    if (!projectDir) {
        console.warn('[LocalizationHook] App directory not found.');
        return;
    }

    const appDir = path.join(iosPlatformPath, projectDir.name);
    const pluginDir = context.opts.plugin.dir;
    const languages = ['en', 'ar'];

    // 2. Copy Localisation/<lang>.lproj/InfoPlist.strings into the Xcode app folder
    languages.forEach(lang => {
        const destLangDir = path.join(appDir, `${lang}.lproj`);
        if (!fs.existsSync(destLangDir)) {
            fs.mkdirSync(destLangDir, { recursive: true });
        }

        const srcFile = path.join(pluginDir, 'Localisation', `${lang}.lproj`, 'InfoPlist.strings');
        const destFile = path.join(destLangDir, 'InfoPlist.strings');

        if (fs.existsSync(srcFile)) {
            fs.copyFileSync(srcFile, destFile);
            console.log(`[LocalizationHook] Successfully copied ${lang} strings to ${destFile}`);
        } else {
            console.warn(`[LocalizationHook] Source file missing: ${srcFile}`);
        }
    });

    // 3. Force CFBundleLocalizations in Info.plist to ['en', 'ar']
    const plistPath = path.join(appDir, `${projectDir.name}-Info.plist`);
    if (fs.existsSync(plistPath)) {
        let content = fs.readFileSync(plistPath, 'utf8');
        const regex = /<key>CFBundleLocalizations<\/key>[\s\S]*?<\/array>/;
        const replacement = `<key>CFBundleLocalizations</key>\n\t<array>\n\t\t<string>en</string>\n\t\t<string>ar</string>\n\t</array>`;

        if (regex.test(content)) {
            content = content.replace(regex, replacement);
        } else {
            content = content.replace('</dict>', `\t${replacement}\n</dict>`);
        }

        fs.writeFileSync(plistPath, content, 'utf8');
        console.log('[LocalizationHook] Info.plist CFBundleLocalizations updated.');
    }
};
