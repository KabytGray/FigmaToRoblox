// ============================================================================
// FigmaToRoblox — Plugin do Figma
// ============================================================================
// Le a arvore selecionada e emite o SCHEMA v2, que o plugin do Roblox consome
// diretamente. Toda a traducao Figma -> Roblox acontece AQUI, onde temos os
// tipos completos da API do Figma. O Worker e apenas um armazem burro.
// ============================================================================

const SCHEMA_VERSION = 2;
const REVIEW_EVERY = 5; // pede avaliacao a cada N exports bem-sucedidos

// ---------------------------------------------------------------------------
// Tipos do schema v2 (espelhado em roblox-plugin/FigmaToRoblox.lua)
// ---------------------------------------------------------------------------
type Rgb255 = [number, number, number]; // canal 0-255, como Color3.fromRGB espera

interface RbxGradient {
  stops: Array<{ t: number; c: Rgb255 }>;
  alpha: Array<{ t: number; a: number }>; // a = transparencia Roblox (0 = opaco)
  rot: number;
}

/** Par (scale, offset) — um lado de um UDim. */
type Udim = [number, number];

/**
 * Geometria derivada das constraints do Figma. Quando presente, o plugin do
 * Roblox usa isso em vez dos offsets crus, e a UI passa a acompanhar o pai.
 */
interface RbxFit {
  px?: Udim; py?: Udim;   // Position
  sx?: Udim; sy?: Udim;   // Size
  anchor?: [number, number];
}

interface RbxText {
  content: string;
  /** Markup de RichText quando o texto tem formatação mista. */
  rich?: string;
  size: number;
  color: Rgb255;
  transparency: number;
  font: string; // nome de Enum.Font
  alignX: "Left" | "Center" | "Right";
  alignY: "Top" | "Center" | "Bottom";
  wrapped: boolean;
  lineHeight?: number; // multiplicador (Roblox LineHeight aceita 1.0 - 3.0)
  autoSize?: "X" | "Y" | "XY";
}

interface RbxLayout {
  dir: "Horizontal" | "Vertical";
  gap: number;
  pad: { t: number; r: number; b: number; l: number };
  alignX: "Left" | "Center" | "Right";
  alignY: "Top" | "Center" | "Bottom";
  /** Auto Layout com wrap vira UIGridLayout em vez de UIListLayout. */
  grid?: { cellW: number; cellH: number; gapX: number; gapY: number };
}

interface RbxNode {
  cls: string;
  name: string;
  x: number;
  y: number;
  w: number;
  h: number;
  z: number;
  rot?: number;
  anchor?: [number, number];
  visible?: boolean;
  clip?: boolean;
  bg?: { c: Rgb255; t: number };
  gradient?: RbxGradient;
  stroke?: { c: Rgb255; th: number; t: number; pos: string };
  corner?: number;
  text?: RbxText;
  image?: {
    key: string; scale: string; t: number;
    /** Borda em pixels do PNG que NAO deve esticar (9-slice). */
    slice?: { l: number; t: number; r: number; b: number };
  };
  layout?: RbxLayout;
  shadow?: { c: Rgb255; ox: number; oy: number; blur: number; spread: number; t: number };
  fit?: RbxFit;
  /** Opacidade de grupo — vira CanvasGroup.GroupTransparency. */
  groupT?: number;
  kids: RbxNode[];
}

// Formas que nao tem equivalente nativo no Roblox — viram PNG.
const RASTERIZE_TYPES = ["VECTOR", "BOOLEAN_OPERATION", "POLYGON", "STAR", "LINE"];

// ---------------------------------------------------------------------------
// Fontes: Figma family -> familia de Enum.Font do Roblox
// ---------------------------------------------------------------------------
interface FontFamily { regular: string; medium: string; bold: string; black: string; }

const BUILDER: FontFamily = { regular: "BuilderSans", medium: "BuilderSansMedium", bold: "BuilderSansBold", black: "BuilderSansExtraBold" };
const GOTHAM: FontFamily = { regular: "Gotham", medium: "GothamMedium", bold: "GothamBold", black: "GothamBlack" };
const SOURCE: FontFamily = { regular: "SourceSans", medium: "SourceSansSemibold", bold: "SourceSansBold", black: "SourceSansBold" };
const ARIAL: FontFamily = { regular: "Arial", medium: "Arial", bold: "ArialBold", black: "ArialBold" };

function mono(n: string): FontFamily { return { regular: n, medium: n, bold: n, black: n }; }

const FONT_MAP: Record<string, FontFamily> = {
  "inter": BUILDER, "sf pro": BUILDER, "sf pro display": BUILDER, "sf pro text": BUILDER,
  "helvetica": ARIAL, "helvetica neue": ARIAL, "arial": ARIAL, "verdana": ARIAL, "tahoma": ARIAL,
  "roboto": { regular: "Roboto", medium: "Roboto", bold: "Roboto", black: "Roboto" },
  "roboto condensed": mono("RobotoCondensed"), "roboto mono": mono("RobotoMono"),
  "source sans pro": SOURCE, "source sans 3": SOURCE,
  "open sans": GOTHAM, "lato": GOTHAM, "poppins": GOTHAM, "montserrat": GOTHAM,
  "work sans": GOTHAM, "dm sans": GOTHAM, "manrope": GOTHAM, "rubik": GOTHAM, "outfit": GOTHAM,
  "nunito": mono("Nunito"), "nunito sans": mono("Nunito"),
  "oswald": mono("Oswald"), "ubuntu": mono("Ubuntu"), "jura": mono("Jura"),
  "merriweather": mono("Merriweather"), "titillium web": mono("TitilliumWeb"),
  "josefin sans": mono("JosefinSans"), "indie flower": mono("IndieFlower"),
  "patrick hand": mono("PatrickHand"), "permanent marker": mono("PermanentMarker"),
  "luckiest guy": mono("LuckiestGuy"), "bangers": mono("Bangers"), "creepster": mono("Creepster"),
  "fredoka one": mono("FredokaOne"), "denk one": mono("DenkOne"), "michroma": mono("Michroma"),
  "special elite": mono("SpecialElite"), "sarpanch": mono("Sarpanch"), "kalam": mono("Kalam"),
  "fondamento": mono("Fondamento"), "grenze gotisch": mono("GrenzeGotisch"),
  "georgia": mono("Georgia"), "garamond": mono("Garamond"),
  "times new roman": mono("Legacy"), "courier new": mono("Code"), "consolas": mono("Code"),
  "jetbrains mono": mono("Code"), "fira code": mono("Code"), "ibm plex mono": mono("Code")
};

function resolveFont(family: string, style: string): string {
  const fam = FONT_MAP[(family || "").toLowerCase().trim()] || BUILDER;
  const s = (style || "").toLowerCase();
  if (s.indexOf("black") >= 0 || s.indexOf("heavy") >= 0 || s.indexOf("extra bold") >= 0 || s.indexOf("extrabold") >= 0) return fam.black;
  if (s.indexOf("bold") >= 0) return fam.bold;
  if (s.indexOf("semi") >= 0 || s.indexOf("medium") >= 0 || s.indexOf("demi") >= 0) return fam.medium;
  return fam.regular;
}

// ---------------------------------------------------------------------------
// Utilitarios
// ---------------------------------------------------------------------------
function rgb(c: { r: number; g: number; b: number }): Rgb255 {
  return [Math.round(c.r * 255), Math.round(c.g * 255), Math.round(c.b * 255)];
}

function clamp01(n: number): number {
  return n < 0 ? 0 : n > 1 ? 1 : n;
}

/** Transparencia Roblox (0 = opaco) a partir de alpha Figma + opacity do paint. */
function toTransparency(alpha: number | undefined, paintOpacity: number | undefined): number {
  const a = (alpha === undefined ? 1 : alpha) * (paintOpacity === undefined ? 1 : paintOpacity);
  return clamp01(1 - a);
}

/** Hash de conteudo (FNV-1a de 2 pistas + tamanho) para deduplicar uploads. */
function hashBytes(bytes: Uint8Array): string {
  let h1 = 0x811c9dc5;
  let h2 = 0x9e3779b9;
  for (let i = 0; i < bytes.length; i++) {
    h1 = Math.imul(h1 ^ bytes[i], 0x01000193) >>> 0;
    h2 = Math.imul(h2 + bytes[i], 0x85ebca6b) >>> 0;
    h2 = (h2 ^ (h2 >>> 13)) >>> 0;
  }
  const hex = (n: number) => (n >>> 0).toString(16);
  return "i" + hex(h1) + hex(h2) + hex(bytes.length);
}

function bytesToBase64(bytes: Uint8Array): string {
  let s = "";
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    const slice = bytes.subarray(i, i + CHUNK);
    let part = "";
    for (let j = 0; j < slice.length; j++) part += String.fromCharCode(slice[j]);
    s += part;
  }
  return btoa(s);
}

/**
 * Origem absoluta do no no canvas. Usar absoluteTransform (e nao x/y) e
 * obrigatorio: filhos de GROUP tem x/y relativo ao pai do grupo, nao ao grupo.
 */
function absOrigin(node: SceneNode): { x: number; y: number } {
  const anyNode = node as any;
  if (anyNode.absoluteTransform) {
    const t = anyNode.absoluteTransform;
    return { x: t[0][2], y: t[1][2] };
  }
  return { x: "x" in node ? node.x : 0, y: "y" in node ? node.y : 0 };
}

/** Centro do no em coordenadas absolutas (respeita rotacao). */
function absCenter(node: SceneNode, w: number, h: number): { x: number; y: number } {
  const anyNode = node as any;
  if (anyNode.absoluteTransform) {
    const t = anyNode.absoluteTransform;
    return {
      x: t[0][0] * (w / 2) + t[0][1] * (h / 2) + t[0][2],
      y: t[1][0] * (w / 2) + t[1][1] * (h / 2) + t[1][2]
    };
  }
  const o = absOrigin(node);
  return { x: o.x + w / 2, y: o.y + h / 2 };
}

function tagOf(name: string, tag: string): boolean {
  return name.indexOf("[" + tag + "]") >= 0;
}

function cleanName(name: string): string {
  const n = name.replace(/\[(IMG|NATIVE|BACK|FRONT|BTN|SCROLL|SLICE)\]/g, "").replace(/[^\w\s\-À-ÿ]/g, "").trim();
  return n.length > 0 ? n.substring(0, 80) : "Element";
}

// ---------------------------------------------------------------------------
// Extracao de propriedades visuais
// ---------------------------------------------------------------------------
function firstVisible<T extends Paint>(paints: readonly Paint[] | typeof figma.mixed): Paint | null {
  if (!paints || paints === figma.mixed) return null;
  const list = paints as readonly Paint[];
  for (let i = list.length - 1; i >= 0; i--) {
    if (list[i].visible !== false) return list[i];
  }
  return null;
}

/**
 * Rotacao do UIGradient a partir do gradientTransform do Figma.
 * O gradientTransform mapeia espaco-do-no -> espaco-do-gradiente; a direcao no
 * espaco do no e a inversa aplicada a (1,0), o que da (e, -d).
 */
function gradientRotation(transform: Transform | undefined): number {
  if (!transform) return 0;
  const d = transform[1][0];
  const e = transform[1][1];
  const deg = (Math.atan2(-d, e) * 180) / Math.PI;
  return Math.round(((deg % 360) + 360) % 360);
}

function extractGradient(paint: GradientPaint): RbxGradient | null {
  const raw = paint.gradientStops;
  if (!raw || raw.length === 0) return null;

  const stops: Array<{ t: number; c: Rgb255 }> = [];
  const alpha: Array<{ t: number; a: number }> = [];
  for (const s of raw) {
    const t = clamp01(s.position);
    stops.push({ t, c: rgb(s.color) });
    alpha.push({ t, a: toTransparency(s.color.a, paint.opacity) });
  }

  // Roblox exige keypoints em t=0 e t=1 e em ordem estritamente crescente.
  stops.sort((a, b) => a.t - b.t);
  alpha.sort((a, b) => a.t - b.t);
  if (stops[0].t > 0) { stops.unshift({ t: 0, c: stops[0].c }); alpha.unshift({ t: 0, a: alpha[0].a }); }
  if (stops[stops.length - 1].t < 1) { stops.push({ t: 1, c: stops[stops.length - 1].c }); alpha.push({ t: 1, a: alpha[alpha.length - 1].a }); }

  return { stops, alpha, rot: gradientRotation(paint.gradientTransform) };
}

function extractCorner(node: SceneNode): number | undefined {
  const anyNode = node as any;
  if (node.type === "ELLIPSE") return -1; // -1 = circulo completo (UICorner 0.5 scale)

  const radii = anyNode.rectangleCornerRadii;
  if (Array.isArray(radii)) {
    const max = Math.max(radii[0] || 0, radii[1] || 0, radii[2] || 0, radii[3] || 0);
    return max > 0 ? max : undefined;
  }
  if ("cornerRadius" in anyNode && anyNode.cornerRadius !== figma.mixed) {
    const r = anyNode.cornerRadius as number;
    return r > 0 ? r : undefined;
  }
  // cornerRadius mixed: pega o maior dos cantos individuais
  const parts = [anyNode.topLeftRadius, anyNode.topRightRadius, anyNode.bottomRightRadius, anyNode.bottomLeftRadius]
    .filter((n: any) => typeof n === "number") as number[];
  if (parts.length > 0) {
    const max = Math.max.apply(null, parts);
    return max > 0 ? max : undefined;
  }
  return undefined;
}

function extractShadow(node: SceneNode): RbxNode["shadow"] {
  const anyNode = node as any;
  if (!("effects" in anyNode) || anyNode.effects === figma.mixed) return undefined;
  for (const ef of anyNode.effects as readonly Effect[]) {
    if (ef.visible === false) continue;
    if (ef.type !== "DROP_SHADOW") continue;
    const s = ef as DropShadowEffect;
    return {
      c: rgb(s.color),
      ox: Math.round(s.offset.x),
      oy: Math.round(s.offset.y),
      blur: Math.round(s.radius),
      spread: Math.round((s as any).spread || 0),
      t: clamp01(1 - s.color.a)
    };
  }
  return undefined;
}

function extractText(node: TextNode): RbxText {
  const fill = firstVisible(node.fills);
  let color: Rgb255 = [255, 255, 255];
  let transparency = 0;
  if (fill && fill.type === "SOLID") {
    // SolidPaint.color e RGB puro; o alpha vive em paint.opacity.
    color = rgb(fill.color);
    transparency = toTransparency(1, fill.opacity);
  }

  const fontName = node.fontName !== figma.mixed ? node.fontName : { family: "Inter", style: "Regular" };
  const fontSize = typeof node.fontSize === "number" ? node.fontSize : 16;

  let lineHeight: number | undefined;
  const lh = node.lineHeight;
  if (lh !== figma.mixed && lh) {
    if (lh.unit === "PIXELS" && fontSize > 0) lineHeight = lh.value / fontSize;
    else if (lh.unit === "PERCENT") lineHeight = lh.value / 100;
  }
  // Roblox aceita LineHeight entre 1 e 3
  if (lineHeight !== undefined) lineHeight = Math.max(1, Math.min(3, lineHeight));

  const alignXMap: Record<string, RbxText["alignX"]> = { LEFT: "Left", CENTER: "Center", RIGHT: "Right", JUSTIFIED: "Left" };
  const alignYMap: Record<string, RbxText["alignY"]> = { TOP: "Top", CENTER: "Center", BOTTOM: "Bottom" };

  let autoSize: RbxText["autoSize"];
  if (node.textAutoResize === "HEIGHT") autoSize = "Y";
  else if (node.textAutoResize === "WIDTH_AND_HEIGHT") autoSize = "XY";

  return {
    content: node.characters || "",
    size: Math.round(fontSize),
    color,
    transparency,
    font: resolveFont(fontName.family, fontName.style),
    alignX: alignXMap[node.textAlignHorizontal] || "Left",
    alignY: alignYMap[node.textAlignVertical] || "Top",
    wrapped: node.textAutoResize === "NONE" || node.textAutoResize === "HEIGHT",
    lineHeight,
    autoSize
  };
}

/**
 * Constraints do Figma -> Position/Size do Roblox.
 *
 * Cada eixo é independente. `MIN` ancora no início, `MAX` no fim (offset
 * negativo a partir da borda oposta), `CENTER` no meio via anchor 0.5,
 * `STRETCH` fixa as duas bordas e faz o tamanho acompanhar o pai, e `SCALE`
 * converte tudo para fração. É o que separa "UI que estica" de "UI que fica
 * parada no canto quando a tela muda".
 */
function axisFit(
  mode: string,
  start: number,   // x ou y do filho
  span: number,    // largura ou altura do filho
  parentSpan: number
): { p: Udim; s: Udim; anchor: number } {
  const safeParent = Math.max(1, parentSpan);
  const end = safeParent - (start + span);

  switch (mode) {
    case "MAX":
      // Ancora na borda final: offset negativo mede a distância até ela.
      return { p: [1, -(end + span)], s: [0, span], anchor: 0 };

    case "CENTER": {
      const centerOffset = (start + span / 2) - safeParent / 2;
      return { p: [0.5, Math.round(centerOffset)], s: [0, span], anchor: 0.5 };
    }

    case "STRETCH":
      // Duas bordas fixas: o tamanho é o do pai menos as duas margens.
      return { p: [0, start], s: [1, -(start + end)], anchor: 0 };

    case "SCALE":
      return {
        p: [start / safeParent, 0],
        s: [span / safeParent, 0],
        anchor: 0,
      };

    default: // MIN
      return { p: [0, start], s: [0, span], anchor: 0 };
  }
}

function extractFit(node: SceneNode, out: RbxNode, parentW: number, parentH: number): RbxFit | undefined {
  const anyNode = node as any;
  if (!anyNode.constraints) return undefined;

  const horizontal = anyNode.constraints.horizontal || "MIN";
  const vertical = anyNode.constraints.vertical || "MIN";

  // Tudo MIN é o comportamento que os offsets crus já dão: não vale o peso.
  if (horizontal === "MIN" && vertical === "MIN") return undefined;

  const x = axisFit(horizontal, out.x, out.w, parentW);
  const y = axisFit(vertical, out.y, out.h, parentH);

  return {
    px: x.p, py: y.p,
    sx: x.s, sy: y.s,
    anchor: [x.anchor, y.anchor],
  };
}

/**
 * Texto com formatação mista -> markup de RichText.
 *
 * Um TextLabel só tem uma cor e um peso. Quando o designer põe uma palavra em
 * negrito no meio da frase, sem RichText isso se perde ou vira três labels.
 */
function extractRichText(node: TextNode, baseColor: Rgb255, baseSize: number): string | undefined {
  let segments: any[];
  try {
    segments = (node as any).getStyledTextSegments(["fontName", "fills", "fontSize"]);
  } catch (e) {
    return undefined;
  }
  if (!segments || segments.length <= 1) return undefined;

  const escape = (s: string) =>
    s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
     .replace(/"/g, "&quot;").replace(/'/g, "&apos;");

  const hex = (c: Rgb255) =>
    "#" + c.map(n => n.toString(16).padStart(2, "0")).join("");

  let markup = "";
  let mixed = false;

  for (const seg of segments) {
    let text = escape(seg.characters || "");
    if (text === "") continue;

    const style = (seg.fontName && seg.fontName.style || "").toLowerCase();
    const bold = style.indexOf("bold") >= 0 || style.indexOf("black") >= 0;
    const italic = style.indexOf("italic") >= 0;

    const fill = seg.fills && seg.fills.length > 0 ? seg.fills[seg.fills.length - 1] : null;
    const color = (fill && fill.type === "SOLID") ? rgb(fill.color) : baseColor;
    const differs = color[0] !== baseColor[0] || color[1] !== baseColor[1] || color[2] !== baseColor[2];

    const size = typeof seg.fontSize === "number" ? Math.round(seg.fontSize) : baseSize;

    const attrs: string[] = [];
    if (differs) attrs.push('color="' + hex(color) + '"');
    if (size !== baseSize) attrs.push('size="' + size + '"');

    if (attrs.length > 0) { text = "<font " + attrs.join(" ") + ">" + text + "</font>"; mixed = true; }
    if (italic) { text = "<i>" + text + "</i>"; mixed = true; }
    if (bold) { text = "<b>" + text + "</b>"; mixed = true; }

    markup += text;
  }

  // Sem diferença real entre os trechos, RichText só adicionaria custo.
  return mixed ? markup : undefined;
}

function extractLayout(node: SceneNode): RbxLayout | undefined {
  const n = node as any;
  if (!("layoutMode" in n) || n.layoutMode === "NONE" || !n.layoutMode) return undefined;

  const horizontal = n.layoutMode === "HORIZONTAL";
  const mainMap: Record<string, string> = { MIN: horizontal ? "Left" : "Top", CENTER: "Center", MAX: horizontal ? "Right" : "Bottom", SPACE_BETWEEN: horizontal ? "Left" : "Top" };
  const crossMap: Record<string, string> = { MIN: horizontal ? "Top" : "Left", CENTER: "Center", MAX: horizontal ? "Bottom" : "Right" };

  const main = mainMap[n.primaryAxisAlignItems] || (horizontal ? "Left" : "Top");
  const cross = crossMap[n.counterAxisAlignItems] || (horizontal ? "Top" : "Left");

  const layout: RbxLayout = {
    dir: horizontal ? "Horizontal" : "Vertical",
    gap: Math.round(n.itemSpacing || 0),
    pad: {
      t: Math.round(n.paddingTop || 0),
      r: Math.round(n.paddingRight || 0),
      b: Math.round(n.paddingBottom || 0),
      l: Math.round(n.paddingLeft || 0)
    },
    alignX: (horizontal ? main : cross) as RbxLayout["alignX"],
    alignY: (horizontal ? cross : main) as RbxLayout["alignY"]
  };

  // Auto Layout com wrap é uma grade, não uma lista: UIListLayout não quebra
  // linha. A célula sai do primeiro filho, que é o padrão da grade.
  if (n.layoutWrap === "WRAP") {
    const first = n.children && n.children.length > 0 ? n.children[0] : null;
    if (first && "width" in first) {
      layout.grid = {
        cellW: Math.max(1, Math.round(first.width)),
        cellH: Math.max(1, Math.round(first.height)),
        gapX: Math.round(n.itemSpacing || 0),
        gapY: Math.round(n.counterAxisSpacing || n.itemSpacing || 0)
      };
    }
  }

  return layout;
}

// ---------------------------------------------------------------------------
// Conversao de um no
// ---------------------------------------------------------------------------
interface Ctx {
  images: Array<{ key: string; bytes: Uint8Array; name: string }>;
  seen: Record<string, boolean>;
  scale: number;
  rasterize: boolean;
  constraints: boolean;
  warnings: string[];
  counts: { nodes: number; images: number; text: number; rich: number; fitted: number; groups: number };
}

function newCtx(scale: number, rasterize: boolean, constraints: boolean): Ctx {
  return {
    images: [], seen: {}, scale, rasterize, constraints, warnings: [],
    counts: { nodes: 0, images: 0, text: 0, rich: 0, fitted: 0, groups: 0 }
  };
}

/** Classes que conseguem exibir uma imagem. */
const IMAGE_CLASSES = ["ImageLabel", "ImageButton"];

function shouldRasterize(node: SceneNode, ctx: Ctx): boolean {
  const name = node.name;

  // Classe forcada que nao exibe imagem implica "nao rasterize". Sem isso o no
  // sairia com `image` preenchido e uma classe que nao sabe o que fazer com ele.
  const forced = node.getPluginData("rbxClass");
  if (forced && IMAGE_CLASSES.indexOf(forced) < 0) return false;
  if (forced && IMAGE_CLASSES.indexOf(forced) >= 0) return true;

  if (tagOf(name, "NATIVE")) return false;
  if (tagOf(name, "IMG") || tagOf(name, "SLICE")) return true;
  if (!ctx.rasterize) return false;

  if (RASTERIZE_TYPES.indexOf(node.type) >= 0) return true;

  // Preenchimento por imagem: rasterizar preserva crop/scale-mode do Figma.
  const anyNode = node as any;
  if ("fills" in anyNode && anyNode.fills !== figma.mixed) {
    for (const p of anyNode.fills as readonly Paint[]) {
      if (p.visible !== false && p.type === "IMAGE") return true;
    }
  }
  return false;
}

/** Classes que o conversor do painel oferece. */
const CLASS_CHOICES = [
  "Frame", "ScrollingFrame", "CanvasGroup",
  "TextLabel", "TextButton", "TextBox",
  "ImageLabel", "ImageButton", "ViewportFrame"
];

/**
 * Classe Roblox alvo.
 *
 * Precedencia: escolha explicita no conversor > tag no nome > inferencia pelo
 * tipo do no. A escolha vai em pluginData, entao viaja com o arquivo .fig e
 * sobrevive a fechar o plugin — clientStorage seria por maquina.
 */
function classFor(node: SceneNode, isImage: boolean): string {
  const forced = node.getPluginData("rbxClass");
  if (forced && CLASS_CHOICES.indexOf(forced) >= 0) return forced;

  const name = node.name;
  if (tagOf(name, "SCROLL")) return "ScrollingFrame";
  if (isImage) return tagOf(name, "BTN") ? "ImageButton" : "ImageLabel";
  if (node.type === "TEXT") return tagOf(name, "BTN") ? "TextButton" : "TextLabel";
  return tagOf(name, "BTN") ? "TextButton" : "Frame";
}

/** Nos marcados como excluidos no painel nao entram no export. */
function isExcluded(node: SceneNode): boolean {
  return node.getPluginData("rbxSkip") === "1";
}

async function convert(
  node: SceneNode,
  origin: { x: number; y: number },
  zIndex: number,
  ctx: Ctx,
  parentW: number,
  parentH: number
): Promise<RbxNode | null> {
  if (node.visible === false && !tagOf(node.name, "NATIVE")) return null;
  if (isExcluded(node)) return null;

  const w = Math.max(1, Math.round("width" in node ? node.width : 100));
  const h = Math.max(1, Math.round("height" in node ? node.height : 100));
  const rotation = "rotation" in node ? Math.round((node as any).rotation || 0) : 0;
  const raster = shouldRasterize(node, ctx);

  const out: RbxNode = {
    cls: classFor(node, raster),
    name: cleanName(node.name),
    x: 0, y: 0, w, h,
    z: tagOf(node.name, "BACK") ? 0 : (tagOf(node.name, "FRONT") ? 999 : zIndex),
    kids: []
  };

  // --- Posicao ------------------------------------------------------------
  // AnchorPoint escolhido a mao no painel tem prioridade. Ao mudar a ancora, a
  // posicao TEM de ser recalculada — senao o elemento salta, porque Position
  // passa a medir um ponto diferente do retangulo.
  const manualAnchor = node.getPluginData("rbxAnchor");
  if (manualAnchor && manualAnchor.indexOf(",") > 0) {
    const parts = manualAnchor.split(",");
    const ax = clamp01(parseFloat(parts[0]) || 0);
    const ay = clamp01(parseFloat(parts[1]) || 0);
    const o = absOrigin(node);

    out.anchor = [ax, ay];
    out.x = Math.round(o.x - origin.x + w * ax);
    out.y = Math.round(o.y - origin.y + h * ay);
    if (rotation !== 0) out.rot = -rotation;
  } else if (rotation !== 0) {
    const c = absCenter(node, w, h);
    out.x = Math.round(c.x - origin.x);
    out.y = Math.round(c.y - origin.y);
    out.anchor = [0.5, 0.5];
    out.rot = -rotation; // Figma gira anti-horario, Roblox horario
  } else {
    const o = absOrigin(node);
    out.x = Math.round(o.x - origin.x);
    out.y = Math.round(o.y - origin.y);
  }

  const opacity = "opacity" in node ? (node as any).opacity : 1;

  // --- Rasterizado --------------------------------------------------------
  if (raster) {
    // exportAsync renderiza os limites VISUAIS do no: stroke externo, sombra e
    // blur entram no PNG. Esses limites sao maiores que width/height, entao
    // dimensionar pelo tamanho do no espreme a arte para dentro (uma borda por
    // fora encolhe e desaparece atras do conteudo). absoluteRenderBounds da a
    // caixa que o PNG realmente ocupa.
    const bounds = (node as any).absoluteRenderBounds as Rect | null | undefined;
    if (bounds && bounds.width > 0 && bounds.height > 0) {
      out.x = Math.round(bounds.x - origin.x);
      out.y = Math.round(bounds.y - origin.y);
      out.w = Math.max(1, Math.round(bounds.width));
      out.h = Math.max(1, Math.round(bounds.height));
      // Os render bounds sao alinhados aos eixos e a rotacao ja esta assada no
      // PNG — reaplicar giraria a arte duas vezes.
      delete out.rot;
      delete out.anchor;
    }

    try {
      const bytes = await node.exportAsync({ format: "PNG", constraint: { type: "SCALE", value: ctx.scale } });
      const key = hashBytes(bytes);
      if (!ctx.seen[key]) {
        ctx.seen[key] = true;
        ctx.images.push({ key, bytes, name: out.name });
      }
      out.image = { key, scale: "Stretch", t: clamp01(1 - opacity) };

      // 9-slice: a borda fica intacta e so o meio estica, o que deixa um painel
      // de loja crescer sem deformar o canto arredondado. A largura da borda vem
      // do proprio raio do canto — e exatamente a regiao que nao pode esticar.
      if (tagOf(node.name, "SLICE")) {
        const pngW = Math.max(2, Math.round(out.w * ctx.scale));
        const pngH = Math.max(2, Math.round(out.h * ctx.scale));
        const corner = extractCorner(node);
        const radius = (corner !== undefined && corner > 0) ? corner : Math.min(out.w, out.h) * 0.25;

        const limit = Math.floor(Math.min(pngW, pngH) / 2) - 1;
        const inset = Math.max(1, Math.min(Math.round(radius * ctx.scale), Math.max(1, limit)));

        out.image.scale = "Slice";
        out.image.slice = { l: inset, t: inset, r: pngW - inset, b: pngH - inset };
      }

      ctx.counts.images++;
    } catch (e: any) {
      ctx.warnings.push('Falha ao rasterizar "' + out.name + '"');
      out.cls = "Frame";
    }
    ctx.counts.nodes++;
    return out;
  }

  // --- Preenchimento ------------------------------------------------------
  const anyNode = node as any;
  const fill = "fills" in anyNode ? firstVisible(anyNode.fills) : null;
  if (fill && node.type !== "TEXT") {
    if (fill.type === "SOLID") {
      // A opacidade do no multiplica a do preenchimento.
      const fillAlpha = (fill.opacity === undefined ? 1 : fill.opacity) * opacity;
      out.bg = { c: rgb(fill.color), t: clamp01(1 - fillAlpha) };
    } else if (fill.type.indexOf("GRADIENT") === 0) {
      const g = extractGradient(fill as GradientPaint);
      if (g) {
        out.gradient = g;
        out.bg = { c: [255, 255, 255], t: 0 };
      }
    }
  }

  // --- Borda --------------------------------------------------------------
  if ("strokes" in anyNode && anyNode.strokes !== figma.mixed) {
    const stroke = firstVisible(anyNode.strokes);
    if (stroke && stroke.type === "SOLID") {
      const weight = anyNode.strokeWeight !== figma.mixed ? anyNode.strokeWeight : 1;
      if (weight > 0) {
        const alignMap: Record<string, string> = { CENTER: "Border", INSIDE: "Inner", OUTSIDE: "Outer" };
        out.stroke = {
          c: rgb(stroke.color),
          th: Math.round(weight),
          t: toTransparency(1, stroke.opacity),
          pos: alignMap[anyNode.strokeAlign] || "Border"
        };
      }
    }
  }

  // --- Cantos, sombra, clip ----------------------------------------------
  const corner = extractCorner(node);
  if (corner !== undefined) out.corner = corner;

  const shadow = extractShadow(node);
  if (shadow) out.shadow = shadow;

  if (anyNode.clipsContent) out.clip = true;

  // --- Texto --------------------------------------------------------------
  if (node.type === "TEXT") {
    out.text = extractText(node as TextNode);
    const rich = extractRichText(node as TextNode, out.text.color, out.text.size);
    if (rich) { out.text.rich = rich; ctx.counts.rich++; }
    ctx.counts.text++;
  }

  // --- Auto Layout --------------------------------------------------------
  const layout = extractLayout(node);
  if (layout) out.layout = layout;

  // --- Constraints --------------------------------------------------------
  if (ctx.constraints) {
    const fit = extractFit(node, out, parentW, parentH);
    if (fit) { out.fit = fit; ctx.counts.fitted++; }
  }

  // --- Opacidade de grupo -------------------------------------------------
  // Um grupo com opacidade < 1 no Figma esmaece como um todo. Aplicar a
  // transparência em cada filho dá resultado diferente onde eles se sobrepõem;
  // CanvasGroup achata primeiro e só então esmaece, que é o comportamento certo.
  //
  // Nunca sobrescreve escolha explícita: se a pessoa fixou a classe no
  // conversor, é ela quem manda.
  const forcedClass = node.getPluginData("rbxClass");
  const hasKids = "children" in anyNode && anyNode.children && anyNode.children.length > 0;

  if (opacity < 1 && hasKids && !forcedClass) {
    out.cls = "CanvasGroup";
    out.groupT = clamp01(1 - opacity);
    if (out.bg) out.bg.t = 0; // a transparência agora é do grupo, não do fundo
    ctx.counts.groups++;
  } else if (opacity < 1 && forcedClass === "CanvasGroup") {
    out.groupT = clamp01(1 - opacity);
    if (out.bg) out.bg.t = 0;
    ctx.counts.groups++;
  }

  // --- Filhos -------------------------------------------------------------
  // children[0] e o mais ao fundo no Figma; ZIndex crescente reproduz a ordem.
  if ("children" in anyNode && anyNode.children) {
    const childOrigin = absOrigin(node);
    const kids = anyNode.children as readonly SceneNode[];
    for (let i = 0; i < kids.length; i++) {
      const child = await convert(kids[i], childOrigin, i + 1, ctx, out.w, out.h);
      if (child) out.kids.push(child);
    }
  }

  // --- Aviso de corte no CanvasGroup --------------------------------------
  // Um CanvasGroup desenha os descendentes numa textura do proprio tamanho:
  // o que passa da borda some, e ClipsDescendants nao muda isso. Numa barra de
  // vida quem costuma vazar e brilho, borda externa e ponta arredondada — o
  // resultado "quase certo" que nao da erro nenhum. Melhor avisar na exportacao
  // do que deixar a pessoa procurando o motivo no Studio.
  if (out.cls === "CanvasGroup" && out.kids.length > 0) {
    let worst = 0;
    for (const kid of out.kids) {
      worst = Math.max(worst, -kid.x, -kid.y,
        (kid.x + kid.w) - out.w, (kid.y + kid.h) - out.h);
    }
    if (worst >= 1) {
      ctx.warnings.push(
        '"' + out.name + '" e CanvasGroup e corta ' + Math.round(worst) +
        'px de filho que passa da borda. Aumente o frame no Figma ou use Frame.'
      );
    }
  }

  ctx.counts.nodes++;
  return out;
}

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------
function selectionOrigin(sel: readonly SceneNode[]): { x: number; y: number } {
  let minX = Infinity;
  let minY = Infinity;
  for (const n of sel) {
    const o = absOrigin(n);
    if (o.x < minX) minX = o.x;
    if (o.y < minY) minY = o.y;
  }
  return { x: minX === Infinity ? 0 : minX, y: minY === Infinity ? 0 : minY };
}

/** Envelope da seleção — serve de "pai" para as constraints das raízes. */
function selectionSize(sel: readonly SceneNode[], origin: { x: number; y: number }) {
  let w = 1;
  let h = 1;
  for (const n of sel) {
    const o = absOrigin(n);
    const nw = "width" in n ? n.width : 0;
    const nh = "height" in n ? n.height : 0;
    w = Math.max(w, o.x - origin.x + nw);
    h = Math.max(h, o.y - origin.y + nh);
  }
  return { w: Math.round(w), h: Math.round(h) };
}

function post(type: string, payload?: any) {
  const msg: any = { type };
  if (payload) for (const k in payload) msg[k] = payload[k];
  figma.ui.postMessage(msg);
}

async function analyze(scale: number, rasterize: boolean, constraints: boolean) {
  const sel = figma.currentPage.selection;
  if (sel.length === 0) { post("error", { message: "Selecione ao menos um frame." }); return; }

  const ctx = newCtx(scale, rasterize, constraints);
  const origin = selectionOrigin(sel);
  const canvas = selectionSize(sel, origin);
  for (let i = 0; i < sel.length; i++) await convert(sel[i], origin, i + 1, ctx, canvas.w, canvas.h);

  let bytes = 0;
  for (const img of ctx.images) bytes += img.bytes.length;

  post("analysis", {
    nodes: ctx.counts.nodes,
    images: ctx.counts.images,
    unique: ctx.images.length,
    text: ctx.counts.text,
    rich: ctx.counts.rich,
    fitted: ctx.counts.fitted,
    groups: ctx.counts.groups,
    sizeKb: Math.round(bytes / 1024),
    warnings: ctx.warnings
  });
}

async function runExport(workerUrl: string, token: string, scale: number, rasterize: boolean, constraints: boolean) {
  const sel = figma.currentPage.selection;
  if (sel.length === 0) { post("error", { message: "Selecione ao menos um frame." }); return; }

  post("progress", { message: "Lendo " + sel.length + " elemento(s)...", pct: 10 });

  const ctx = newCtx(scale, rasterize, constraints);
  const origin = selectionOrigin(sel);
  const canvas = selectionSize(sel, origin);
  const roots: RbxNode[] = [];

  for (let i = 0; i < sel.length; i++) {
    try {
      const node = await convert(sel[i], origin, i + 1, ctx, canvas.w, canvas.h);
      if (node) roots.push(node);
    } catch (e: any) {
      ctx.warnings.push('Ignorado "' + sel[i].name + '": ' + (e && e.message ? e.message : "erro"));
    }
  }

  if (roots.length === 0) { post("error", { message: "Nada exportavel na selecao." }); return; }

  post("progress", { message: "Codificando " + ctx.images.length + " imagem(ns)...", pct: 45 });

  const images: Record<string, string> = {};
  const imageNames: Record<string, string> = {};
  for (const img of ctx.images) {
    images[img.key] = bytesToBase64(img.bytes);
    imageNames[img.key] = img.name;
  }

  post("progress", { message: "Enviando para o servidor...", pct: 75 });

  const base = workerUrl.replace(/\/+$/, "");
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token) headers["Authorization"] = "Bearer " + token;

  const resp = await fetch(base + "/api/upload", {
    method: "POST",
    headers,
    body: JSON.stringify({
      schemaVersion: SCHEMA_VERSION,
      exportedAt: new Date().toISOString(),
      documentName: figma.root.name,
      pageName: figma.currentPage.name,
      rootName: sel.length === 1 ? cleanName(sel[0].name) : cleanName(figma.currentPage.name),
      canvasWidth: Math.round(Math.max.apply(null, roots.map(r => r.x + r.w))),
      canvasHeight: Math.round(Math.max.apply(null, roots.map(r => r.y + r.h))),
      roots,
      images,
      imageNames
    })
  });

  if (!resp.ok) throw new Error("Servidor respondeu " + resp.status);
  const result: any = await resp.json();
  if (!result.success) throw new Error(result.error || "Erro desconhecido no servidor");

  // Pede avaliacao a cada REVIEW_EVERY exports, e nunca mais se dispensado.
  const exportCount = ((await figma.clientStorage.getAsync("exportCount")) || 0) + 1;
  await figma.clientStorage.setAsync("exportCount", exportCount);
  const reviewDone = (await figma.clientStorage.getAsync("reviewDone")) === true;

  post("export-complete", {
    exportId: result.exportId,
    nodes: ctx.counts.nodes,
    images: ctx.images.length,
    cached: result.cachedImages || 0,
    pending: result.pendingImages || 0,
    warnings: ctx.warnings,
    askReview: !reviewDone && exportCount % REVIEW_EVERY === 0
  });
}

// ---------------------------------------------------------------------------
// Mensagens da UI
// ---------------------------------------------------------------------------
// Largo o suficiente para trilha de secoes + preview lado a lado. Um painel de
// 380px obrigaria a empilhar tudo, que e o que tornava a UI um rolo.
figma.showUI(__html__, { width: 820, height: 700, title: "FigmaToRoblox" });

const ALL_TAGS = ["IMG", "NATIVE", "BTN", "SCROLL", "FRONT", "BACK"];

function reportSelection() {
  const sel = figma.currentPage.selection;

  // Quais tags ja estao aplicadas em alguma das camadas selecionadas — a UI
  // usa isso para marcar os botoes e animar a remocao.
  const active: string[] = [];
  for (const tag of ALL_TAGS) {
    for (const node of sel) {
      if (tagOf(node.name, tag)) { active.push(tag); break; }
    }
  }

  post("selection", {
    count: sel.length,
    name: sel.length === 1 ? sel[0].name : "",
    active
  });
}

// ---------------------------------------------------------------------------
// Miniaturas, preview e inspecao — o que alimenta a trilha e a grade do painel
// ---------------------------------------------------------------------------

/** PNG do no como data URI, limitado por largura. */
async function thumbOf(node: SceneNode, width: number): Promise<string> {
  const bytes = await node.exportAsync({
    format: "PNG",
    constraint: { type: "WIDTH", value: width }
  });
  return "data:image/png;base64," + bytesToBase64(bytes);
}

/** Frames/componentes de nivel superior da pagina — as "secoes" exportaveis. */
async function scanSections() {
  const wanted = ["FRAME", "COMPONENT", "COMPONENT_SET", "GROUP", "SECTION", "INSTANCE"];
  const found = figma.currentPage.children.filter(n => wanted.indexOf(n.type) >= 0 && n.visible !== false);

  post("progress", { message: "Lendo " + found.length + " secao(oes)...", pct: 20 });

  const items = [];
  for (const node of found.slice(0, 40)) {
    let thumb = "";
    try { thumb = await thumbOf(node, 132); } catch (e) { /* no sem area exportavel */ }
    items.push({
      id: node.id,
      name: node.name,
      type: node.type,
      w: Math.round("width" in node ? node.width : 0),
      h: Math.round("height" in node ? node.height : 0),
      thumb
    });
  }

  post("sections", { items });
}

/** Achata a selecao numa lista, para o painel listar e converter classes. */
function flatten(nodes: readonly SceneNode[], depth: number, out: any[]) {
  for (const node of nodes) {
    if (node.visible === false) continue;

    const anyNode = node as any;
    out.push({
      id: node.id,
      name: node.name,
      type: node.type,
      depth,
      cls: classFor(node, RASTERIZE_TYPES.indexOf(node.type) >= 0),
      forced: node.getPluginData("rbxClass") || "",
      anchor: node.getPluginData("rbxAnchor") || "",
      skipped: isExcluded(node)
    });

    if (out.length > 400) return;
    if (anyNode.children) flatten(anyNode.children as readonly SceneNode[], depth + 1, out);
  }
}

/** Preview da selecao + lista de elementos + imagens que serao enviadas. */
async function buildPreview(scale: number, rasterize: boolean) {
  const sel = figma.currentPage.selection;
  if (sel.length === 0) { post("preview", { empty: true }); return; }

  post("progress", { message: "Gerando preview...", pct: 30 });

  const target = sel[0];
  let thumb = "";
  try { thumb = await thumbOf(target, 620); } catch (e) { /* sem area */ }

  const elements: any[] = [];
  flatten(sel, 0, elements);

  // Reaproveita a conversao real para saber exatamente quais imagens sobem.
  const ctx = newCtx(scale, rasterize, false);
  const origin = selectionOrigin(sel);
  const canvas = selectionSize(sel, origin);
  for (let i = 0; i < sel.length; i++) {
    try { await convert(sel[i], origin, i + 1, ctx, canvas.w, canvas.h); } catch (e) { /* ignora */ }
  }

  const images = ctx.images.map(img => ({
    key: img.key,
    name: img.name,
    kb: Math.round(img.bytes.length / 1024),
    thumb: "data:image/png;base64," + bytesToBase64(img.bytes)
  }));

  post("preview", {
    name: target.name,
    w: Math.round("width" in target ? target.width : 0),
    h: Math.round("height" in target ? target.height : 0),
    thumb,
    count: sel.length,
    // Ids do que esta REALMENTE selecionado. `elements` traz a arvore achatada
    // para listar; aplicar classe nela converteria todos os descendentes.
    selIds: sel.map(n => n.id),
    elements,
    images,
    nodes: ctx.counts.nodes,
    // AnchorPoint do primeiro selecionado — e o que a bola do widget mostra.
    anchor: target.getPluginData("rbxAnchor") || ""
  });
}

// ---------------------------------------------------------------------------
// Biblioteca de projetos — o plugin faz de ponte porque o iframe da UI nao
// alcanca a rede (CSP), mas o sandbox do plugin alcanca.
// ---------------------------------------------------------------------------
async function api(workerUrl: string, route: string, method: string, body?: any, token?: string) {
  const headers: Record<string, string> = {};
  if (body) headers["Content-Type"] = "application/json";
  if (token) headers["Authorization"] = "Bearer " + token;

  const resp = await fetch(workerUrl.replace(/\/+$/, "") + route, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined
  });

  const data: any = await resp.json();
  return { status: resp.status, data };
}

async function listProjects(workerUrl: string) {
  try {
    const { data } = await api(workerUrl, "/api/projects", "GET");
    post("projects", { projects: data.projects || [], usage: data.usage, ttlDays: data.ttlDays });
  } catch (e: any) {
    post("projects", { projects: [], error: e && e.message ? e.message : "falha ao listar" });
  }
}

/** Salva a selecao atual como projeto: miniatura + arvore v2 + metadados. */
async function saveProject(msg: any) {
  const sel = figma.currentPage.selection;
  if (sel.length === 0) { post("error", { message: "Selecione um frame para salvar." }); return; }

  post("progress", { message: "Salvando projeto...", pct: 30 });

  const ctx = newCtx(msg.scale || 2, msg.rasterize !== false, msg.constraints === true);
  const origin = selectionOrigin(sel);
  const canvas = selectionSize(sel, origin);
  const roots: RbxNode[] = [];
  for (let i = 0; i < sel.length; i++) {
    const node = await convert(sel[i], origin, i + 1, ctx, canvas.w, canvas.h);
    if (node) roots.push(node);
  }

  let thumb = "";
  try { thumb = await thumbOf(sel[0], 240); } catch (e) { /* sem area exportavel */ }

  const images: Record<string, string> = {};
  for (const img of ctx.images) images[img.key] = bytesToBase64(img.bytes);

  const { status, data } = await api(msg.workerUrl, "/api/projects", "POST", {
    id: msg.id || "",
    name: msg.name || sel[0].name,
    thumb,
    components: ctx.counts.nodes,
    images: ctx.images.length,
    exportId: msg.exportId || "",
    data: {
      schemaVersion: SCHEMA_VERSION,
      documentName: figma.root.name,
      pageName: figma.currentPage.name,
      rootName: cleanName(sel[0].name),
      canvasWidth: canvas.w,
      canvasHeight: canvas.h,
      roots,
      images
    }
  }, msg.token);

  if (status === 507) {
    post("storage-full", { message: data.error });
    return;
  }
  if (!data.success) { post("error", { message: data.error || "Falha ao salvar" }); return; }

  post("project-saved", { project: data.project });
  await listProjects(msg.workerUrl);
}

figma.on("selectionchange", reportSelection);

figma.ui.onmessage = async (msg: any) => {
  try {
    if (msg.type === "load-settings") {
      post("settings-loaded", {
        workerUrl: (await figma.clientStorage.getAsync("workerUrl")) || "",
        token: (await figma.clientStorage.getAsync("token")) || "",
        scale: (await figma.clientStorage.getAsync("scale")) || 2,
        rasterize: (await figma.clientStorage.getAsync("rasterize")) !== false,
        constraints: (await figma.clientStorage.getAsync("constraints")) === true,
        uploaderCmd: (await figma.clientStorage.getAsync("uploaderCmd")) || "",
        theme: (await figma.clientStorage.getAsync("theme")) || "dark",
        accent: (await figma.clientStorage.getAsync("accent")) || "blue",
        robloxUserId: (await figma.clientStorage.getAsync("robloxUserId")) || ""
      });
      reportSelection();
      return;
    }

    if (msg.type === "save-settings") {
      await figma.clientStorage.setAsync("workerUrl", msg.workerUrl || "");
      await figma.clientStorage.setAsync("token", msg.token || "");
      await figma.clientStorage.setAsync("scale", msg.scale || 2);
      await figma.clientStorage.setAsync("rasterize", msg.rasterize !== false);
      await figma.clientStorage.setAsync("uploaderCmd", msg.uploaderCmd || "");
      await figma.clientStorage.setAsync("constraints", msg.constraints === true);
      await figma.clientStorage.setAsync("theme", msg.theme || "dark");
      await figma.clientStorage.setAsync("accent", msg.accent || "blue");
      await figma.clientStorage.setAsync("robloxUserId", msg.robloxUserId || "");
      return;
    }

    if (msg.type === "analyze") {
      await analyze(msg.scale || 2, msg.rasterize !== false, msg.constraints === true);
      return;
    }

    if (msg.type === "export") {
      if (!msg.workerUrl) { post("error", { message: "Configure a URL do servidor." }); return; }
      await runExport(msg.workerUrl, msg.token || "", msg.scale || 2,
        msg.rasterize !== false, msg.constraints === true);
      return;
    }

    if (msg.type === "tag") {
      const sel = figma.currentPage.selection;
      for (const node of sel) {
        const stripped = node.name.replace(/\[(IMG|NATIVE|BACK|FRONT|BTN|SCROLL|SLICE)\]\s*/g, "").trim();
        node.name = msg.tag ? "[" + msg.tag + "] " + stripped : stripped;
      }
      // Renomear nao dispara selectionchange: reportamos na mao para a UI
      // atualizar quais tags estao ativas.
      reportSelection();
      post("progress", { message: sel.length + " camada(s) atualizada(s).", pct: 100 });
      return;
    }

    if (msg.type === "list-projects") { await listProjects(msg.workerUrl); return; }
    if (msg.type === "save-project") { await saveProject(msg); return; }

    if (msg.type === "delete-project") {
      await api(msg.workerUrl, "/api/project/" + msg.id, "DELETE", undefined, msg.token);
      await listProjects(msg.workerUrl);
      return;
    }

    if (msg.type === "extend-project") {
      await api(msg.workerUrl, "/api/project/" + msg.id + "/extend", "POST", undefined, msg.token);
      await listProjects(msg.workerUrl);
      post("progress", { message: "Projeto mantido por mais 3 dias.", pct: 100 });
      return;
    }

    // Carregar reenvia o projeto salvo como um export novo, para o Studio poder
    // importar sem depender de o export original ainda existir.
    if (msg.type === "open-project") {
      const { data } = await api(msg.workerUrl, "/api/project/" + msg.id, "GET");
      if (!data.project) { post("error", { message: data.error || "Projeto nao encontrado" }); return; }

      post("progress", { message: "Reenviando " + data.project.name + "...", pct: 50 });

      const headers: Record<string, string> = { "Content-Type": "application/json" };
      if (msg.token) headers["Authorization"] = "Bearer " + msg.token;

      const resp = await fetch(msg.workerUrl.replace(/\/+$/, "") + "/api/upload", {
        method: "POST",
        headers,
        body: JSON.stringify({ ...data.data, exportedAt: new Date().toISOString() })
      });
      const result: any = await resp.json();

      if (result.success) {
        post("project-opened", {
          project: data.project,
          exportId: result.exportId,
          pending: result.pendingImages || 0
        });
      } else {
        post("error", { message: result.error || "Falha ao reenviar" });
      }
      return;
    }

    if (msg.type === "scan") { await scanSections(); return; }

    if (msg.type === "preview") {
      await buildPreview(msg.scale || 2, msg.rasterize !== false);
      return;
    }

    // Seleciona a secao no canvas e enquadra — clicar na trilha deve levar o
    // usuario ate lá, nao so mudar o preview.
    if (msg.type === "focus-section") {
      const node = await figma.getNodeByIdAsync(msg.id);
      if (node && "type" in node) {
        figma.currentPage.selection = [node as SceneNode];
        figma.viewport.scrollAndZoomIntoView([node as SceneNode]);
      }
      return;
    }

    if (msg.type === "set-class") {
      for (const id of msg.ids || []) {
        const node = await figma.getNodeByIdAsync(id);
        if (node && "setPluginData" in node) {
          (node as SceneNode).setPluginData("rbxClass", msg.cls || "");
        }
      }
      post("progress", { message: (msg.ids || []).length + " elemento(s) -> " + (msg.cls || "automatico"), pct: 100 });
      return;
    }

    // Nudge move as camadas de verdade no Figma. Mexer no arquivo e o que faz
    // o ajuste ser visivel na hora, em vez de um numero que so vale no export.
    if (msg.type === "nudge") {
      const sel = figma.currentPage.selection;
      if (sel.length === 0) { post("error", { message: "Selecione algo para deslocar." }); return; }

      const dx = msg.dx || 0;
      const dy = msg.dy || 0;
      let moved = 0;
      for (const node of sel) {
        if ("x" in node && "y" in node) {
          (node as any).x += dx;
          (node as any).y += dy;
          moved++;
        }
      }
      post("progress", { message: moved + " camada(s) deslocada(s) " + dx + ", " + dy, pct: 100 });
      return;
    }

    if (msg.type === "set-anchor") {
      const value = (msg.ax === null || msg.ax === undefined) ? "" : msg.ax + "," + msg.ay;
      for (const id of msg.ids || []) {
        const node = await figma.getNodeByIdAsync(id);
        if (node && "setPluginData" in node) {
          (node as SceneNode).setPluginData("rbxAnchor", value);
        }
      }
      post("progress", {
        message: value === "" ? "AnchorPoint automatico" : "AnchorPoint " + value,
        pct: 100
      });
      return;
    }

    if (msg.type === "toggle-skip") {
      for (const id of msg.ids || []) {
        const node = await figma.getNodeByIdAsync(id);
        if (node && "setPluginData" in node) {
          const scene = node as SceneNode;
          scene.setPluginData("rbxSkip", isExcluded(scene) ? "" : "1");
        }
      }
      return;
    }

    if (msg.type === "review-done") {
      await figma.clientStorage.setAsync("reviewDone", true);
      return;
    }

    if (msg.type === "close") figma.closePlugin();
  } catch (e: any) {
    post("error", { message: e && e.message ? e.message : String(e) });
  }
};
