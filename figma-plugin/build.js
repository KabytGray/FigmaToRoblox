// Copia a UI para dist/ e injeta os assets embutidos.
// O avatar vai como data URI para nao depender de rede nem de CSP do Figma.
const fs = require("fs");
const path = require("path");

const root = __dirname;
const src = path.join(root, "src", "ui.html");
const out = path.join(root, "dist", "ui.html");
const avatarPath = path.join(root, "assets", "avatar.b64");

const iconsPath = path.join(root, "assets", "classicons.json");

let html = fs.readFileSync(src, "utf8");

if (html.includes("__AVATAR_B64__")) {
  if (!fs.existsSync(avatarPath)) {
    console.error("assets/avatar.b64 nao encontrado — o avatar ficara vazio.");
    html = html.replace(/__AVATAR_B64__/g, "");
  } else {
    html = html.replace(/__AVATAR_B64__/g, fs.readFileSync(avatarPath, "utf8").trim());
  }
}

// Icones de classe do proprio Studio, extraidos de
// content/studio_svg_textures/Shared/InsertableObjects/Dark/Standard.
// Regenerar com: node tools/extract-icons.js
if (html.includes("__CLASS_ICONS__")) {
  if (!fs.existsSync(iconsPath)) {
    console.error("assets/classicons.json nao encontrado — os icones de classe ficarao vazios.");
    html = html.replace(/__CLASS_ICONS__/g, "{}");
  } else {
    html = html.replace(/__CLASS_ICONS__/g, fs.readFileSync(iconsPath, "utf8").trim());
  }
}

fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, html);
console.log("dist/ui.html  " + Math.round(html.length / 1024) + " KB");
