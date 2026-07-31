// ============================================================================
// FigmaToRoblox — Cloudflare Worker (schema v2)
// ============================================================================
// O Worker nao traduz nada: o plugin do Figma ja envia a arvore no formato que
// o plugin do Roblox consome. Aqui so guardamos, resolvemos IDs de imagem e
// servimos.
//
// Layout no KV:
//   exp:<id>      -> { schemaVersion, meta..., roots, imageKeys[] }
//   pending:<id>  -> { <imageKey>: <base64> }   (some quando tudo resolve)
//   res:<id>      -> { <imageKey>: "rbxassetid://..." }
//   img:<key>     -> "rbxassetid://..."   cache GLOBAL, evita re-upload
//   __list__      -> [ resumo dos ultimos 50 exports ]
//   __latest__    -> <id>
// ============================================================================

export interface Env {
  FIGMA_DATA: KVNamespace;
  AUTH_TOKEN?: string;
}

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization"
};

const MAX_LIST = 50;

// ---------------------------------------------------------------------------
// Projetos (biblioteca do plugin do Figma)
// ---------------------------------------------------------------------------
// Um projeto e um trabalho salvo: miniatura, metadados e a arvore v2. Some
// sozinho depois de 3 dias — o KV expira a chave por conta propria, entao nao
// existe rotina de limpeza para dar errado.
const PROJECT_TTL_DAYS = 3;
const PROJECT_TTL = PROJECT_TTL_DAYS * 24 * 60 * 60;
const WARN_BEFORE_MS = 12 * 60 * 60 * 1000;   // avisa 12h antes de expirar
const MAX_PROJECTS = 40;
const MAX_TOTAL_BYTES = 60 * 1024 * 1024;     // teto de armazenamento

interface ProjectMeta {
  id: string;
  name: string;
  thumb: string;
  components: number;
  images: number;
  createdAt: string;
  updatedAt: string;
  expiresAt: string;
  exportId?: string;
  bytes: number;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });

    const url = new URL(request.url);
    const path = url.pathname;

    try {
      if (path === "/api/health") {
        return json({ status: "ok", schemaVersion: 2, auth: Boolean(env.AUTH_TOKEN) });
      }

      if (request.method === "POST" && path === "/api/upload") {
        const denied = authGuard(request, env);
        if (denied) return denied;
        return await handleUpload(request, env);
      }

      if (request.method === "POST" && path === "/api/resolve-images") {
        const denied = authGuard(request, env);
        if (denied) return denied;
        return await handleResolve(request, env);
      }

      // --- biblioteca de projetos -----------------------------------------
      if (request.method === "GET" && path === "/api/projects") return await listProjects(env);

      if (request.method === "POST" && path === "/api/projects") {
        const denied = authGuard(request, env);
        if (denied) return denied;
        return await saveProject(request, env);
      }

      if (path.startsWith("/api/project/")) {
        const rest = path.slice("/api/project/".length);
        const [id, action] = rest.split("/");

        if (request.method === "GET" && !action) return await loadProject(id, env);

        if (request.method === "DELETE" && !action) {
          const denied = authGuard(request, env);
          if (denied) return denied;
          return await deleteProject(id, env);
        }

        if (request.method === "POST" && action === "extend") {
          const denied = authGuard(request, env);
          if (denied) return denied;
          return await extendProject(id, env);
        }
      }

      // --- apoiadores ------------------------------------------------------
      if (request.method === "GET" && path === "/api/supporters") return await listSupporters(env);

      if (request.method === "POST" && path === "/api/supporters") {
        const denied = authGuard(request, env);
        if (denied) return denied;
        return await recordDonation(request, env);
      }

      if (request.method === "GET" && path === "/api/exports") return await handleList(env);
      if (request.method === "GET" && path === "/api/latest") return await handleLatest(env);
      if (request.method === "GET" && path === "/api/pending") return await handlePending(env);

      if (request.method === "GET" && path.startsWith("/api/status/")) {
        return await handleStatus(path.slice("/api/status/".length), env);
      }

      if (request.method === "GET" && path.startsWith("/api/export/")) {
        return await handleGet(path.slice("/api/export/".length), env);
      }

      return json({ error: "Rota nao encontrada" }, 404);
    } catch (e: any) {
      return json({ error: e && e.message ? e.message : String(e) }, 500);
    }
  }
};

// ---------------------------------------------------------------------------
// Auth (opcional: so ativa se AUTH_TOKEN estiver configurado)
// ---------------------------------------------------------------------------
function authGuard(request: Request, env: Env): Response | null {
  if (!env.AUTH_TOKEN) return null;
  const header = request.headers.get("Authorization") || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (token !== env.AUTH_TOKEN) return json({ error: "Nao autorizado" }, 401);
  return null;
}

// ---------------------------------------------------------------------------
// Upload — recebe a arvore v2 do Figma
// ---------------------------------------------------------------------------
async function handleUpload(request: Request, env: Env): Promise<Response> {
  const body: any = await request.json();

  if (body.schemaVersion !== 2) {
    return json({ error: "Schema incompativel. Atualize o plugin do Figma (esperado v2)." }, 400);
  }
  if (!Array.isArray(body.roots) || body.roots.length === 0) {
    return json({ error: "Nenhum elemento recebido." }, 400);
  }

  const id = randId();
  const images: Record<string, string> = body.images || {};
  const imageKeys = Object.keys(images);

  // Dedup: chaves ja enviadas antes reaproveitam o assetId do cache global.
  const resolved: Record<string, string> = {};
  const pending: Record<string, string> = {};
  for (const key of imageKeys) {
    const cached = await env.FIGMA_DATA.get("img:" + key);
    if (cached) resolved[key] = cached;
    else pending[key] = images[key];
  }

  const doc = {
    schemaVersion: 2,
    exportId: id,
    exportedAt: body.exportedAt || new Date().toISOString(),
    documentName: body.documentName || "Sem nome",
    pageName: body.pageName || "",
    rootName: body.rootName || body.documentName || "Import",
    canvasWidth: body.canvasWidth || 0,
    canvasHeight: body.canvasHeight || 0,
    roots: body.roots,
    imageKeys,
    imageNames: body.imageNames || {}
  };

  const writes: Promise<any>[] = [
    env.FIGMA_DATA.put("exp:" + id, JSON.stringify(doc)),
    env.FIGMA_DATA.put("__latest__", id)
  ];
  if (Object.keys(resolved).length > 0) {
    writes.push(env.FIGMA_DATA.put("res:" + id, JSON.stringify(resolved)));
  }
  if (Object.keys(pending).length > 0) {
    writes.push(env.FIGMA_DATA.put("pending:" + id, JSON.stringify(pending)));
  }
  await Promise.all(writes);

  await pushToList(env, {
    id,
    documentName: doc.documentName,
    pageName: doc.pageName,
    rootName: doc.rootName,
    exportedAt: doc.exportedAt,
    elementCount: countNodes(doc.roots),
    imageCount: imageKeys.length,
    pendingCount: Object.keys(pending).length
  });

  return json({
    success: true,
    exportId: id,
    totalImages: imageKeys.length,
    cachedImages: Object.keys(resolved).length,
    pendingImages: Object.keys(pending).length
  });
}

// ---------------------------------------------------------------------------
// Leitura — arvore com os rbxassetid ja embutidos
// ---------------------------------------------------------------------------
async function handleGet(rawId: string, env: Env): Promise<Response> {
  const id = rawId.trim();
  if (!id) return json({ error: "ID obrigatorio" }, 400);

  const raw = await env.FIGMA_DATA.get("exp:" + id);
  if (!raw) return json({ error: "Export nao encontrado: " + id }, 404);

  const doc = JSON.parse(raw);
  const resRaw = await env.FIGMA_DATA.get("res:" + id);
  const resolved: Record<string, string> = resRaw ? JSON.parse(resRaw) : {};

  const missing: string[] = [];
  const roots = inlineImages(doc.roots, resolved, missing);

  return json({
    schemaVersion: 2,
    exportId: doc.exportId,
    exportedAt: doc.exportedAt,
    documentName: doc.documentName,
    pageName: doc.pageName,
    rootName: doc.rootName,
    canvasWidth: doc.canvasWidth,
    canvasHeight: doc.canvasHeight,
    roots,
    imageCount: Object.keys(resolved).length,
    missingImages: missing.length,
    ready: missing.length === 0
  });
}

async function handleStatus(rawId: string, env: Env): Promise<Response> {
  const id = rawId.trim();
  const raw = await env.FIGMA_DATA.get("exp:" + id);
  if (!raw) return json({ error: "Export nao encontrado" }, 404);

  const doc = JSON.parse(raw);
  const pendingRaw = await env.FIGMA_DATA.get("pending:" + id);
  const pendingCount = pendingRaw ? Object.keys(JSON.parse(pendingRaw)).length : 0;

  return json({
    exportId: id,
    ready: pendingCount === 0,
    pendingImages: pendingCount,
    totalImages: (doc.imageKeys || []).length,
    exportedAt: doc.exportedAt
  });
}

async function handleLatest(env: Env): Promise<Response> {
  const id = await env.FIGMA_DATA.get("__latest__");
  if (!id) return json({ error: "Nenhum export ainda" }, 404);
  return await handleStatusWithMeta(id, env);
}

async function handleStatusWithMeta(id: string, env: Env): Promise<Response> {
  const raw = await env.FIGMA_DATA.get("exp:" + id);
  if (!raw) return json({ error: "Export nao encontrado" }, 404);

  const doc = JSON.parse(raw);
  const pendingRaw = await env.FIGMA_DATA.get("pending:" + id);
  const pendingCount = pendingRaw ? Object.keys(JSON.parse(pendingRaw)).length : 0;

  return json({
    exportId: id,
    rootName: doc.rootName,
    documentName: doc.documentName,
    exportedAt: doc.exportedAt,
    elementCount: countNodes(doc.roots),
    totalImages: (doc.imageKeys || []).length,
    pendingImages: pendingCount,
    ready: pendingCount === 0
  });
}

async function handleList(env: Env): Promise<Response> {
  return json(await getList(env));
}

// ---------------------------------------------------------------------------
// Fila de upload consumida pelo uploader.js local
// ---------------------------------------------------------------------------
async function handlePending(env: Env): Promise<Response> {
  const list = await getList(env);
  const out: any[] = [];

  for (const item of list) {
    const raw = await env.FIGMA_DATA.get("pending:" + item.id);
    if (!raw) continue;
    const images = JSON.parse(raw);
    if (Object.keys(images).length === 0) continue;

    const doc = await env.FIGMA_DATA.get("exp:" + item.id);
    const names = doc ? JSON.parse(doc).imageNames || {} : {};
    out.push({ id: item.id, documentName: item.documentName, images, names });
  }

  return json(out);
}

async function handleResolve(request: Request, env: Env): Promise<Response> {
  const body: any = await request.json();
  const exportId: string = body.exportId;
  const resolved: Record<string, string> = body.resolved;

  if (!exportId || !resolved || typeof resolved !== "object") {
    return json({ error: "exportId e resolved sao obrigatorios" }, 400);
  }

  const resRaw = await env.FIGMA_DATA.get("res:" + exportId);
  const current: Record<string, string> = resRaw ? JSON.parse(resRaw) : {};
  for (const key in resolved) current[key] = resolved[key];
  await env.FIGMA_DATA.put("res:" + exportId, JSON.stringify(current));

  // Alimenta o cache global — a mesma imagem nunca sobe duas vezes.
  await Promise.all(Object.keys(resolved).map(key =>
    env.FIGMA_DATA.put("img:" + key, resolved[key])
  ));

  // Retira da fila o que ja resolveu.
  const pendingRaw = await env.FIGMA_DATA.get("pending:" + exportId);
  let remaining = 0;
  if (pendingRaw) {
    const pending = JSON.parse(pendingRaw);
    for (const key in resolved) delete pending[key];
    remaining = Object.keys(pending).length;
    if (remaining === 0) await env.FIGMA_DATA.delete("pending:" + exportId);
    else await env.FIGMA_DATA.put("pending:" + exportId, JSON.stringify(pending));
  }

  await patchList(env, exportId, remaining);

  return json({ success: true, remaining, ready: remaining === 0 });
}

// ---------------------------------------------------------------------------
// Apoiadores
// ---------------------------------------------------------------------------
// Doacoes chegam de fora (a place de doacao avisa aqui, ou o autor registra a
// mao). O plugin so LE esta lista — escrever exige token, senao qualquer um
// entraria no podio.
interface Supporter {
  userId: number;
  name: string;
  robux: number;
  firstAt: string;
  lastAt: string;
}

async function supporterList(env: Env): Promise<Supporter[]> {
  const raw = await env.FIGMA_DATA.get("__supporters__");
  return raw ? JSON.parse(raw) : [];
}

async function listSupporters(env: Env): Promise<Response> {
  const list = await supporterList(env);

  // Ordena por total; empate vai para quem apoiou primeiro, que e mais justo
  // do que deixar a ordem ao acaso da tabela.
  const ranked = list.slice().sort((a, b) =>
    b.robux - a.robux || a.firstAt.localeCompare(b.firstAt)
  );

  return json({
    supporters: ranked.map((s, i) => ({ ...s, rank: i + 1 })),
    total: ranked.reduce((sum, s) => sum + s.robux, 0),
    count: ranked.length,
  });
}

async function recordDonation(request: Request, env: Env): Promise<Response> {
  const body: any = await request.json();
  const userId = Number(body.userId);
  const robux = Number(body.robux);

  if (!Number.isFinite(userId) || userId <= 0) return json({ error: "userId invalido" }, 400);
  if (!Number.isFinite(robux) || robux <= 0) return json({ error: "robux invalido" }, 400);

  const list = await supporterList(env);
  const now = new Date().toISOString();
  const existing = list.find(s => s.userId === userId);

  if (existing) {
    // Soma em vez de substituir: quem doa varias vezes sobe no podio.
    existing.robux += robux;
    existing.lastAt = now;
    if (body.name) existing.name = String(body.name).slice(0, 40);
  } else {
    list.push({
      userId,
      name: String(body.name || ("User" + userId)).slice(0, 40),
      robux,
      firstAt: now,
      lastAt: now,
    });
  }

  await env.FIGMA_DATA.put("__supporters__", JSON.stringify(list));
  return json({ success: true, total: list.reduce((s, x) => s + x.robux, 0) });
}

// ---------------------------------------------------------------------------
// Projetos
// ---------------------------------------------------------------------------
async function projectIndex(env: Env): Promise<ProjectMeta[]> {
  const raw = await env.FIGMA_DATA.get("__projects__");
  const list: ProjectMeta[] = raw ? JSON.parse(raw) : [];

  // O KV expira o conteudo sozinho, mas o indice nao: filtra o que ja venceu
  // para a lista nunca mostrar projeto morto.
  const now = Date.now();
  return list.filter(p => new Date(p.expiresAt).getTime() > now);
}

async function writeIndex(env: Env, list: ProjectMeta[]): Promise<void> {
  await env.FIGMA_DATA.put("__projects__", JSON.stringify(list));
}

function usageOf(list: ProjectMeta[]): number {
  return list.reduce((sum, p) => sum + (p.bytes || 0), 0);
}

async function listProjects(env: Env): Promise<Response> {
  const list = await projectIndex(env);
  const now = Date.now();

  return json({
    projects: list
      .map(p => ({
        ...p,
        // Quanto falta para sumir, para a UI avisar antes e nao depois.
        expiresInMs: new Date(p.expiresAt).getTime() - now,
        expiringSoon: new Date(p.expiresAt).getTime() - now < WARN_BEFORE_MS,
      }))
      .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)),
    usage: {
      bytes: usageOf(list),
      maxBytes: MAX_TOTAL_BYTES,
      count: list.length,
      maxCount: MAX_PROJECTS,
      full: usageOf(list) >= MAX_TOTAL_BYTES || list.length >= MAX_PROJECTS,
    },
    ttlDays: PROJECT_TTL_DAYS,
  });
}

async function saveProject(request: Request, env: Env): Promise<Response> {
  const body: any = await request.json();
  if (!body.name) return json({ error: "name obrigatorio" }, 400);

  const list = await projectIndex(env);
  // Reaproveita o id so quando o projeto ainda existe; senao seria "atualizar"
  // algo que ja expirou e o indice ficaria com uma entrada fantasma.
  const requested: string = typeof body.id === "string" ? body.id : "";
  const id: string = (requested && list.some(p => p.id === requested)) ? requested : randId();
  const payload = JSON.stringify(body.data || {});
  const bytes = payload.length + (body.thumb || "").length;

  const others = list.filter(p => p.id !== id);

  // Recusa antes de gravar: aceitar e depois estourar deixaria o indice
  // inconsistente com o que existe de fato no KV.
  if (others.length >= MAX_PROJECTS) {
    return json({ error: "limite de " + MAX_PROJECTS + " projetos atingido", full: true }, 507);
  }
  if (usageOf(others) + bytes > MAX_TOTAL_BYTES) {
    return json({ error: "limite de armazenamento atingido", full: true }, 507);
  }

  const now = new Date();
  const existing = list.find(p => p.id === id);
  const meta: ProjectMeta = {
    id,
    name: String(body.name).slice(0, 80),
    thumb: body.thumb || "",
    components: body.components || 0,
    images: body.images || 0,
    createdAt: existing ? existing.createdAt : now.toISOString(),
    updatedAt: now.toISOString(),
    expiresAt: new Date(now.getTime() + PROJECT_TTL * 1000).toISOString(),
    exportId: body.exportId || undefined,
    bytes,
  };

  // expirationTtl deixa o proprio KV apagar: sem rotina de limpeza para falhar.
  await env.FIGMA_DATA.put("proj:" + id, payload, { expirationTtl: PROJECT_TTL });
  await env.FIGMA_DATA.put("projthumb:" + id, meta.thumb, { expirationTtl: PROJECT_TTL });
  await writeIndex(env, [meta, ...others]);

  return json({ success: true, project: meta });
}

async function loadProject(id: string, env: Env): Promise<Response> {
  const list = await projectIndex(env);
  const meta = list.find(p => p.id === id);
  if (!meta) return json({ error: "Projeto nao encontrado ou expirado" }, 404);

  const raw = await env.FIGMA_DATA.get("proj:" + id);
  if (!raw) return json({ error: "Conteudo expirou" }, 404);

  const thumb = await env.FIGMA_DATA.get("projthumb:" + id);
  return json({ project: { ...meta, thumb: thumb || "" }, data: JSON.parse(raw) });
}

async function deleteProject(id: string, env: Env): Promise<Response> {
  const list = await projectIndex(env);
  await env.FIGMA_DATA.delete("proj:" + id);
  await env.FIGMA_DATA.delete("projthumb:" + id);
  await writeIndex(env, list.filter(p => p.id !== id));
  return json({ success: true });
}

async function extendProject(id: string, env: Env): Promise<Response> {
  const list = await projectIndex(env);
  const meta = list.find(p => p.id === id);
  if (!meta) return json({ error: "Projeto nao encontrado" }, 404);

  const raw = await env.FIGMA_DATA.get("proj:" + id);
  if (!raw) return json({ error: "Conteudo ja expirou" }, 404);

  // Reescreve com TTL novo: o KV nao tem "tocar validade" sem reescrever.
  const thumb = await env.FIGMA_DATA.get("projthumb:" + id);
  await env.FIGMA_DATA.put("proj:" + id, raw, { expirationTtl: PROJECT_TTL });
  await env.FIGMA_DATA.put("projthumb:" + id, thumb || "", { expirationTtl: PROJECT_TTL });

  meta.expiresAt = new Date(Date.now() + PROJECT_TTL * 1000).toISOString();
  await writeIndex(env, list);

  return json({ success: true, project: meta });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function inlineImages(nodes: any[], resolved: Record<string, string>, missing: string[]): any[] {
  return nodes.map(node => {
    const copy = { ...node };
    if (node.image && node.image.key) {
      const assetId = resolved[node.image.key];
      if (assetId) copy.image = { ...node.image, id: assetId };
      else { missing.push(node.image.key); copy.image = { ...node.image, id: "" }; }
    }
    if (Array.isArray(node.kids) && node.kids.length > 0) {
      copy.kids = inlineImages(node.kids, resolved, missing);
    }
    return copy;
  });
}

function countNodes(nodes: any[]): number {
  let total = 0;
  for (const node of nodes) {
    total += 1;
    if (Array.isArray(node.kids)) total += countNodes(node.kids);
  }
  return total;
}

async function getList(env: Env): Promise<any[]> {
  const raw = await env.FIGMA_DATA.get("__list__");
  return raw ? JSON.parse(raw) : [];
}

async function pushToList(env: Env, entry: any): Promise<void> {
  const list = await getList(env);
  list.unshift(entry);
  if (list.length > MAX_LIST) list.length = MAX_LIST;
  await env.FIGMA_DATA.put("__list__", JSON.stringify(list));
}

async function patchList(env: Env, id: string, pendingCount: number): Promise<void> {
  const list = await getList(env);
  const entry = list.find((item: any) => item.id === id);
  if (!entry) return;
  entry.pendingCount = pendingCount;
  await env.FIGMA_DATA.put("__list__", JSON.stringify(list));
}

function randId(): string {
  const alphabet = "abcdefghijkmnpqrstuvwxyz23456789"; // sem l/o/0/1
  let id = "";
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  for (let i = 0; i < 8; i++) id += alphabet[bytes[i] % alphabet.length];
  return id;
}

function json(data: any, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" }
  });
}
