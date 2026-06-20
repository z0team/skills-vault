#!/usr/bin/env node

import { intro, outro, select, multiselect, spinner, note, isCancel, cancel, log } from '@clack/prompts';
import pc from 'picocolors';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
    console.clear();
    const asciiArt = `
███████╗██╗  ██╗██╗██╗     ██╗     ███████╗
██╔════╝██║ ██╔╝██║██║     ██║     ██╔════╝
███████╗█████╔╝ ██║██║     ██║     ███████╗
╚════██║██╔═██╗ ██║██║     ██║     ╚════██║
███████║██║  ██╗██║███████╗███████╗███████║
╚══════╝╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚══════╝
`;
    console.log(pc.cyan(asciiArt));
    intro('skills');

    // Load registry
    const registryPath = path.join(__dirname, 'registry.json');
    if (!fs.existsSync(registryPath)) {
        cancel('Registry file not found. Ensure you are running this from the repository root or via npx.');
        process.exit(1);
    }

    const registry = JSON.parse(fs.readFileSync(registryPath, 'utf-8'));
    const packs = registry.packs || [];

    if (packs.length === 0) {
        cancel('No packs found in the registry.');
        process.exit(1);
    }

    log.step(`Source: https://github.com/z0team/skills-vault.git`);
    log.step(`Found ${packs.length} packs`);

    // 1. Ask for scope
    const scope = await select({
        message: 'Where would you like to install the skills?',
        options: [
            { value: 'local', label: 'Local Workspace', hint: 'Installs to the current directory (recommended)' },
            { value: 'global', label: 'Global', hint: 'Installs globally for all projects (system path)' }
        ],
    });
    if (isCancel(scope)) { cancel('Operation cancelled.'); process.exit(0); }

    // 2. Ask for agents
    const agents = await multiselect({
        message: 'Which AI agents are you using?',
        options: [
            { value: 'claude-code', label: 'Claude Code' },
            { value: 'cursor', label: 'Cursor' },
            { value: 'roo', label: 'Roo Code (Cline)' },
            { value: 'windsurf', label: 'Windsurf' },
            { value: 'copilot', label: 'GitHub Copilot' },
            { value: 'continue', label: 'Continue.dev' },
            { value: 'zed', label: 'Zed AI' },
            { value: 'trae', label: 'Trae IDE' },
            { value: 'opencode', label: 'OpenCode' },
            { value: 'codex', label: 'Codex' },
            { value: 'agy', label: 'Agy' },
        ],
        required: true,
    });
    if (isCancel(agents)) { cancel('Operation cancelled.'); process.exit(0); }

    // 3. Ask for packs
    const packOptions = packs.map(p => {
        let desc = p.description.replace(/\n/g, ' ');
        if (desc.length > 60) desc = desc.substring(0, 57) + '...';
        return {
            value: p.id,
            label: p.id,
            hint: desc
        };
    });

    const selectedPacks = await multiselect({
        message: 'Which skill packs would you like to install?',
        options: [
            { value: 'ALL', label: pc.green('Install ALL packs'), hint: 'Everything available' },
            ...packOptions
        ],
        required: true,
    });
    if (isCancel(selectedPacks)) { cancel('Operation cancelled.'); process.exit(0); }

    const finalPacks = selectedPacks.includes('ALL') ? packs.map(p => p.id) : selectedPacks;

    // 4. Install files
    const s = spinner();
    s.start('Installing skills...');

    const homeDir = process.env.HOME || process.env.USERPROFILE;
    const currentDir = process.cwd();
    let hasMcp = false;

    for (const agent of agents) {
        let destDir = currentDir;
        if (scope === 'global') {
            if (agent === 'cursor') {
                note('Cursor does not support global rules natively. Installing locally instead.', 'Warning');
                destDir = currentDir;
            } else {
                destDir = homeDir;
            }
        }

        // Ensure dest dir exists
        if (!fs.existsSync(destDir)) {
            fs.mkdirSync(destDir, { recursive: true });
        }

        for (const pid of finalPacks) {
            const srcDir = path.join(__dirname, 'dist', pid, agent);
            if (fs.existsSync(srcDir)) {
                // Copy all contents from srcDir to destDir recursively
                copyRecursiveSync(srcDir, destDir);
            }

            // Check MCP
            const packInfo = packs.find(p => p.id === pid);
            if (packInfo && packInfo.mcp_servers && packInfo.mcp_servers.length > 0) {
                hasMcp = true;
            }
        }
    }

    s.stop('Installation complete!');

    if (hasMcp) {
        note(
            'Some installed packs require an MCP server (e.g. @21st-dev/cli).\n' +
            'Please check the pack documentation to configure your agent properly.',
            'Action Required'
        );
    }

    outro(pc.green('🎉 You are all set! Happy coding!'));
}

function copyRecursiveSync(src, dest) {
    if (fs.statSync(src).isDirectory()) {
        if (!fs.existsSync(dest)) fs.mkdirSync(dest, { recursive: true });
        fs.readdirSync(src).forEach(childItemName => {
            copyRecursiveSync(path.join(src, childItemName), path.join(dest, childItemName));
        });
    } else {
        // Only overwrite if we really want to, but for now we just write
        fs.copyFileSync(src, dest);
    }
}

main().catch(err => {
    console.error(pc.red('\nAn error occurred:'), err);
    process.exit(1);
});
