// Contrôles du panel staff et des scripts Lunatic, à lancer avant chaque commit :
//   node tools/check-panel.js
// 1. Noms déclarés deux fois au niveau global dans les scripts web de lunatic_admin (tous partagent la même portée :
//    un doublon remplace silencieusement l'autre, ou casse tout le fichier pour const / let).
// 2. Fichiers web, CSS, serveur et client oubliés dans le manifeste ou dans index.html.
// 3. Chaînes Lua avec \' (règle du projet : guillemets doubles quand le texte contient une apostrophe).
// 4. Équilibre des blocs Lua (function / if / for / while / do … end) des resources maison.
// Code de sortie 1 s'il y a une erreur.

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const scripts = path.join(root, 'resources', '[8_Creation_script]');
const admin = path.join(scripts, 'lunatic_admin');
const web = path.join(admin, 'web');
let errors = 0;

function fail(message) {
    errors += 1;
    console.log('ERREUR  ' + message);
}

function walk(dir, ext, out = []) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            if (entry.name !== 'node_modules' && entry.name !== 'vendor') walk(full, ext, out);
        } else if (entry.name.endsWith(ext)) {
            out.push(full);
        }
    }
    return out;
}

// ---------- 1. Noms globaux du panel ----------

const index = fs.readFileSync(path.join(web, 'index.html'), 'utf8');
const loaded = [...index.matchAll(/<script src="([^"]+)"/g)].map((m) => m[1]).filter((f) => !f.startsWith('vendor/'));
const names = new Map();

for (const file of loaded) {
    const full = path.join(web, file);
    if (!fs.existsSync(full)) {
        fail(`index.html charge ${file}, qui n'existe pas`);
        continue;
    }
    for (const line of fs.readFileSync(full, 'utf8').split('\n')) {
        const m = line.match(/^(?:async\s+)?function\s+([A-Za-z_$][\w$]*)|^(?:const|let|var)\s+([A-Za-z_$][\w$]*)/);
        if (!m) continue;
        const name = m[1] || m[2];
        if (!names.has(name)) names.set(name, []);
        names.get(name).push(file);
    }
}

for (const [name, files] of names) {
    if (files.length > 1) fail(`nom global « ${name} » déclaré plusieurs fois : ${files.join(', ')}`);
}

// ---------- 2. Fichiers déclarés ----------

const manifest = fs.readFileSync(path.join(admin, 'fxmanifest.lua'), 'utf8');

for (const file of fs.readdirSync(web).filter((f) => f.endsWith('.js'))) {
    if (!loaded.includes(file)) fail(`web/${file} n'est pas chargé par index.html`);
    if (!manifest.includes(`'web/${file}'`)) fail(`web/${file} n'est pas dans le manifeste de lunatic_admin`);
}

for (const file of fs.readdirSync(path.join(web, 'css')).filter((f) => f.endsWith('.css'))) {
    if (!index.includes(`href="css/${file}"`)) fail(`web/css/${file} n'est pas chargé par index.html`);
}

// Fichiers Lua serveur / client de chaque resource maison absents de leur manifeste
for (const resource of fs.readdirSync(scripts, { withFileTypes: true }).filter((d) => d.isDirectory())) {
    const dir = path.join(scripts, resource.name);
    const fx = path.join(dir, 'fxmanifest.lua');
    if (!fs.existsSync(fx)) continue;
    const text = fs.readFileSync(fx, 'utf8');
    for (const side of ['server', 'client']) {
        const sideDir = path.join(dir, side);
        if (!fs.existsSync(sideDir) || text.includes(`'${side}/*.lua'`)) continue;
        for (const file of fs.readdirSync(sideDir).filter((f) => f.endsWith('.lua'))) {
            if (!text.includes(`'${side}/${file}'`)) fail(`${resource.name}/${side}/${file} n'est pas dans son manifeste`);
        }
    }
}

// ---------- 3 et 4. Lua des resources maison ----------

const KEYWORD = /\b(function|if|for|while|do|repeat|end|until)\b/g;

function luaBalance(source) {
    // retire commentaires et chaînes pour compter les mots-clés
    const clean = source
        .replace(/--\[(=*)\[[\s\S]*?\]\1\]/g, '')
        .replace(/\[(=*)\[[\s\S]*?\]\1\]/g, '""')
        .replace(/--[^\n]*/g, '')
        .replace(/"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'/g, '""');
    let depth = 0;
    let pendingLoop = 0;
    for (const m of clean.matchAll(KEYWORD)) {
        const word = m[1];
        if (word === 'function' || word === 'if' || word === 'repeat') depth += 1;
        else if (word === 'for' || word === 'while') { depth += 1; pendingLoop += 1; }
        else if (word === 'do') { if (pendingLoop > 0) pendingLoop -= 1; else depth += 1; }
        else if (word === 'end' || word === 'until') depth -= 1;
        if (depth < 0) return depth;
    }
    return depth;
}

for (const file of walk(scripts, '.lua')) {
    const rel = path.relative(scripts, file);
    if (!/^lunatic_/.test(rel)) continue;
    const source = fs.readFileSync(file, 'utf8');
    source.split(/\r?\n/).forEach((line, i) => {
        const code = line.replace(/--.*$/, '');
        if (code.includes("\\'")) fail(`${rel}:${i + 1} : chaîne avec \\' (utiliser des guillemets doubles)`);
    });
    const depth = luaBalance(source);
    if (depth !== 0) fail(`${rel} : blocs Lua déséquilibrés (${depth > 0 ? depth + ' end manquant(s)' : -depth + ' end en trop'})`);
}

console.log(errors ? `\n${errors} erreur(s).` : `OK : ${names.size} noms globaux sans doublon, fichiers déclarés, Lua équilibré.`);
process.exit(errors ? 1 : 0);
