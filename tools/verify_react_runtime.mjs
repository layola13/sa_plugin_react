import { readFile } from "node:fs/promises";
import path from "node:path";

class ClassList {
  constructor(element) {
    this.element = element;
    this.items = new Set();
  }

  sync() {
    const text = [...this.items].join(" ");
    this.element.className = text;
    if (text.length === 0) {
      this.element.attributes.delete("class");
    } else {
      this.element.attributes.set("class", text);
    }
  }

  add(name) {
    this.items.add(String(name));
    this.sync();
  }

  remove(name) {
    this.items.delete(String(name));
    this.sync();
  }

  toggle(name, force) {
    const key = String(name);
    const enabled = force === undefined ? !this.items.has(key) : Boolean(force);
    if (enabled) {
      this.items.add(key);
    } else {
      this.items.delete(key);
    }
    this.sync();
    return enabled;
  }

  contains(name) {
    return this.items.has(String(name));
  }
}

class Element {
  constructor(tagName) {
    this.tagName = tagName.toLowerCase();
    this.children = [];
    this.parentNode = null;
    this.attributes = new Map();
    this.listeners = new Map();
    this.classList = new ClassList(this);
    this.className = "";
    this.value = "";
    this.checked = false;
    this.selected = false;
    this.multiple = false;
    this.disabled = false;
    this.readOnly = false;
    this.required = false;
    this.open = false;
    this.hidden = false;
    this.inert = false;
    this.draggable = false;
    this.controls = false;
    this.muted = false;
    this.loop = false;
    this.autoplay = false;
    this.playsInline = false;
    this.disablePictureInPicture = false;
    this.disableRemotePlayback = false;
    this.noValidate = false;
    this.formNoValidate = false;
    this.isMap = false;
    this.reversed = false;
    this.default = false;
    this.min = "";
    this.max = "";
    this.step = "";
    this.low = "";
    this.high = "";
    this.optimum = "";
    this.size = "";
    this.span = "";
    this.rows = "";
    this.cols = "";
    this.wrap = "";
    this.width = "";
    this.height = "";
    this.start = "";
    this.placeholder = "";
    this.pattern = "";
    this.accept = "";
    this.capture = "";
    this.dirName = "";
    this.label = "";
    this.maxLength = "";
    this.minLength = "";
    this.inputMode = "";
    this.enterKeyHint = "";
    this.autoCapitalize = "";
    this.autocorrect = "";
    this.contentEditable = "";
    this.spellcheck = true;
    this.translate = true;
    this.nonce = "";
    this.title = "";
    this.lang = "";
    this.dir = "";
    this.role = "";
    this.accessKey = "";
    this.tabIndex = "";
    this.slot = "";
    this.part = "";
    this.popover = "";
    this.itemProp = "";
    this.itemScope = false;
    this.itemType = "";
    this.itemID = "";
    this.itemRef = "";
    this.htmlFor = "";
    this.rowSpan = "";
    this.colSpan = "";
    this.headers = "";
    this.scope = "";
    this.abbr = "";
    this.dateTime = "";
    this.charset = "";
    this.httpEquiv = "";
    this.content = "";
    this.cite = "";
    this.src = "";
    this.alt = "";
    this.longDesc = "";
    this.coords = "";
    this.shape = "";
    this.sizes = "";
    this.href = "";
    this.hreflang = "";
    this.action = "";
    this.poster = "";
    this.download = "";
    this.ping = "";
    this.rel = "";
    this.preload = "";
    this.media = "";
    this.integrity = "";
    this.as = "";
    this.blocking = "";
    this.type = "";
    this.srcset = "";
    this.useMap = "";
    this.imageSrcset = "";
    this.imageSizes = "";
    this.crossOrigin = "";
    this.controlsList = "";
    this.loading = "";
    this.decoding = "";
    this.fetchPriority = "";
    this.referrerPolicy = "";
    this.kind = "";
    this.srcLang = "";
    this.autocomplete = "";
    this.acceptCharset = "";
    this.enctype = "";
    this.method = "";
    this.target = "";
    this.formAction = "";
    this.formEnctype = "";
    this.formMethod = "";
    this.formTarget = "";
    this.textContent = "";
    this.innerHTML = "";
  }

  get options() {
    if (this.tagName !== "select") return [];
    return findAll(this, (node) => node.tagName === "option");
  }

  get value() {
    if (this.tagName === "select" && this.multiple) {
      return this.options.filter((option) => option.selected).map(optionValue).join(",");
    }
    return this._value;
  }

  set value(next) {
    const text = String(next ?? "");
    if (this.tagName === "select" && this.multiple) {
      const values = new Set(text.split(/[\n,]/).map((item) => item.trim()).filter(Boolean));
      for (const option of this.options) {
        option.selected = values.has(optionValue(option));
      }
      this._value = text;
      return;
    }
    this._value = text;
  }

  appendChild(child) {
    if (child.parentNode) child.parentNode.removeChild(child);
    child.parentNode = this;
    this.children.push(child);
    return child;
  }

  removeChild(child) {
    const idx = this.children.indexOf(child);
    if (idx >= 0) {
      this.children.splice(idx, 1);
      child.parentNode = null;
    }
    return child;
  }

  remove() {
    if (this.parentNode) this.parentNode.removeChild(this);
  }

  focus() {
    if (globalThis.document) globalThis.document.activeElement = this;
  }

  setAttribute(key, value) {
    const attr = String(key);
    const text = String(value);
    this.attributes.set(attr, text);
    if (attr === "id") this.id = text;
    if (attr === "name") this.name = text;
    if (attr === "nonce") this.nonce = text;
    if (attr === "value") this.value = text;
    if (attr === "min") this.min = text;
    if (attr === "max") this.max = text;
    if (attr === "step") this.step = text;
    if (attr === "low") this.low = text;
    if (attr === "high") this.high = text;
    if (attr === "optimum") this.optimum = text;
    if (attr === "size") this.size = text;
    if (attr === "span") this.span = text;
    if (attr === "rows") this.rows = text;
    if (attr === "cols") this.cols = text;
    if (attr === "wrap") this.wrap = text;
    if (attr === "width") this.width = text;
    if (attr === "height") this.height = text;
    if (attr === "start") this.start = text;
    if (attr === "placeholder") this.placeholder = text;
    if (attr === "pattern") this.pattern = text;
    if (attr === "accept") this.accept = text;
    if (attr === "capture") this.capture = text;
    if (attr === "dirname") this.dirName = text;
    if (attr === "label") this.label = text;
    if (attr === "maxlength") this.maxLength = text;
    if (attr === "minlength") this.minLength = text;
    if (attr === "inputmode") this.inputMode = text;
    if (attr === "enterkeyhint") this.enterKeyHint = text;
    if (attr === "autocapitalize") this.autoCapitalize = text;
    if (attr === "autocorrect") this.autocorrect = text;
    if (attr === "contenteditable") this.contentEditable = text;
    if (attr === "spellcheck") this.spellcheck = text !== "false";
    if (attr === "translate") this.translate = text.trim().toLowerCase() !== "no";
    if (attr === "title") this.title = text;
    if (attr === "lang") this.lang = text;
    if (attr === "dir") this.dir = text;
    if (attr === "role") this.role = text;
    if (attr === "accesskey") this.accessKey = text;
    if (attr === "tabindex") this.tabIndex = text;
    if (attr === "slot") this.slot = text;
    if (attr === "part") this.part = text;
    if (attr === "popover") this.popover = text;
    if (attr === "itemprop") this.itemProp = text;
    if (attr === "itemscope") this.itemScope = true;
    if (attr === "itemtype") this.itemType = text;
    if (attr === "itemid") this.itemID = text;
    if (attr === "itemref") this.itemRef = text;
    if (attr === "for") this.htmlFor = text;
    if (attr === "rowspan") this.rowSpan = text;
    if (attr === "colspan") this.colSpan = text;
    if (attr === "headers") this.headers = text;
    if (attr === "scope") this.scope = text;
    if (attr === "abbr") this.abbr = text;
    if (attr === "datetime") this.dateTime = text;
    if (attr === "charset") this.charset = text;
    if (attr === "http-equiv") this.httpEquiv = text;
    if (attr === "content") this.content = text;
    if (attr === "cite") this.cite = text;
    if (attr === "src") this.src = text;
    if (attr === "alt") this.alt = text;
    if (attr === "longdesc") this.longDesc = text;
    if (attr === "coords") this.coords = text;
    if (attr === "shape") this.shape = text;
    if (attr === "sizes") this.sizes = text;
    if (attr === "href") this.href = text;
    if (attr === "hreflang") this.hreflang = text;
    if (attr === "action") this.action = text;
    if (attr === "poster") this.poster = text;
    if (attr === "download") this.download = text;
    if (attr === "ping") this.ping = text;
    if (attr === "rel") this.rel = text;
    if (attr === "preload") this.preload = text;
    if (attr === "media") this.media = text;
    if (attr === "integrity") this.integrity = text;
    if (attr === "as") this.as = text;
    if (attr === "blocking") this.blocking = text;
    if (attr === "type") this.type = text;
    if (attr === "srcset") this.srcset = text;
    if (attr === "usemap") this.useMap = text;
    if (attr === "imagesrcset") this.imageSrcset = text;
    if (attr === "imagesizes") this.imageSizes = text;
    if (attr === "crossorigin") this.crossOrigin = text;
    if (attr === "controlslist") this.controlsList = text;
    if (attr === "loading") this.loading = text;
    if (attr === "decoding") this.decoding = text;
    if (attr === "fetchpriority") this.fetchPriority = text;
    if (attr === "referrerpolicy") this.referrerPolicy = text;
    if (attr === "kind") this.kind = text;
    if (attr === "srclang") this.srcLang = text;
    if (attr === "autocomplete") this.autocomplete = text;
    if (attr === "accept-charset") this.acceptCharset = text;
    if (attr === "enctype") this.enctype = text;
    if (attr === "method") this.method = text;
    if (attr === "target") this.target = text;
    if (attr === "formaction") this.formAction = text;
    if (attr === "formenctype") this.formEnctype = text;
    if (attr === "formmethod") this.formMethod = text;
    if (attr === "formtarget") this.formTarget = text;
    if (attr === "checked") this.checked = true;
    if (attr === "selected") this.selected = true;
    if (attr === "multiple") this.multiple = true;
    if (attr === "disabled") this.disabled = true;
    if (attr === "readonly") this.readOnly = true;
    if (attr === "required") this.required = true;
    if (attr === "open") this.open = true;
    if (attr === "hidden") this.hidden = true;
    if (attr === "inert") this.inert = true;
    if (attr === "draggable") this.draggable = true;
    if (attr === "controls") this.controls = true;
    if (attr === "muted") this.muted = true;
    if (attr === "loop") this.loop = true;
    if (attr === "autoplay") this.autoplay = true;
    if (attr === "playsinline") this.playsInline = true;
    if (attr === "disablePictureInPicture") this.disablePictureInPicture = true;
    if (attr === "disableRemotePlayback") this.disableRemotePlayback = true;
    if (attr === "novalidate") this.noValidate = true;
    if (attr === "formnovalidate") this.formNoValidate = true;
    if (attr === "ismap") this.isMap = true;
    if (attr === "reversed") this.reversed = true;
    if (attr === "default") this.default = true;
    if (attr === "class") {
      this.className = text;
      this.classList.items = new Set(text.split(/\s+/).filter(Boolean));
    }
  }

  getAttribute(key) {
    const attr = String(key);
    return this.attributes.has(attr) ? this.attributes.get(attr) : null;
  }

  removeAttribute(key) {
    const attr = String(key);
    this.attributes.delete(attr);
    if (attr === "id") this.id = "";
    if (attr === "name") this.name = "";
    if (attr === "nonce") this.nonce = "";
    if (attr === "value") this.value = "";
    if (attr === "min") this.min = "";
    if (attr === "max") this.max = "";
    if (attr === "step") this.step = "";
    if (attr === "low") this.low = "";
    if (attr === "high") this.high = "";
    if (attr === "optimum") this.optimum = "";
    if (attr === "size") this.size = "";
    if (attr === "span") this.span = "";
    if (attr === "rows") this.rows = "";
    if (attr === "cols") this.cols = "";
    if (attr === "wrap") this.wrap = "";
    if (attr === "width") this.width = "";
    if (attr === "height") this.height = "";
    if (attr === "start") this.start = "";
    if (attr === "placeholder") this.placeholder = "";
    if (attr === "pattern") this.pattern = "";
    if (attr === "accept") this.accept = "";
    if (attr === "capture") this.capture = "";
    if (attr === "dirname") this.dirName = "";
    if (attr === "label") this.label = "";
    if (attr === "maxlength") this.maxLength = "";
    if (attr === "minlength") this.minLength = "";
    if (attr === "inputmode") this.inputMode = "";
    if (attr === "enterkeyhint") this.enterKeyHint = "";
    if (attr === "autocapitalize") this.autoCapitalize = "";
    if (attr === "autocorrect") this.autocorrect = "";
    if (attr === "contenteditable") this.contentEditable = "";
    if (attr === "spellcheck") this.spellcheck = true;
    if (attr === "translate") this.translate = true;
    if (attr === "title") this.title = "";
    if (attr === "lang") this.lang = "";
    if (attr === "dir") this.dir = "";
    if (attr === "role") this.role = "";
    if (attr === "accesskey") this.accessKey = "";
    if (attr === "tabindex") this.tabIndex = "";
    if (attr === "slot") this.slot = "";
    if (attr === "part") this.part = "";
    if (attr === "popover") this.popover = "";
    if (attr === "itemprop") this.itemProp = "";
    if (attr === "itemscope") this.itemScope = false;
    if (attr === "itemtype") this.itemType = "";
    if (attr === "itemid") this.itemID = "";
    if (attr === "itemref") this.itemRef = "";
    if (attr === "for") this.htmlFor = "";
    if (attr === "rowspan") this.rowSpan = "";
    if (attr === "colspan") this.colSpan = "";
    if (attr === "headers") this.headers = "";
    if (attr === "scope") this.scope = "";
    if (attr === "abbr") this.abbr = "";
    if (attr === "datetime") this.dateTime = "";
    if (attr === "charset") this.charset = "";
    if (attr === "http-equiv") this.httpEquiv = "";
    if (attr === "content") this.content = "";
    if (attr === "cite") this.cite = "";
    if (attr === "src") this.src = "";
    if (attr === "alt") this.alt = "";
    if (attr === "longdesc") this.longDesc = "";
    if (attr === "coords") this.coords = "";
    if (attr === "shape") this.shape = "";
    if (attr === "sizes") this.sizes = "";
    if (attr === "href") this.href = "";
    if (attr === "hreflang") this.hreflang = "";
    if (attr === "action") this.action = "";
    if (attr === "poster") this.poster = "";
    if (attr === "download") this.download = "";
    if (attr === "ping") this.ping = "";
    if (attr === "rel") this.rel = "";
    if (attr === "preload") this.preload = "";
    if (attr === "media") this.media = "";
    if (attr === "integrity") this.integrity = "";
    if (attr === "as") this.as = "";
    if (attr === "blocking") this.blocking = "";
    if (attr === "type") this.type = "";
    if (attr === "srcset") this.srcset = "";
    if (attr === "usemap") this.useMap = "";
    if (attr === "imagesrcset") this.imageSrcset = "";
    if (attr === "imagesizes") this.imageSizes = "";
    if (attr === "crossorigin") this.crossOrigin = "";
    if (attr === "controlslist") this.controlsList = "";
    if (attr === "loading") this.loading = "";
    if (attr === "decoding") this.decoding = "";
    if (attr === "fetchpriority") this.fetchPriority = "";
    if (attr === "referrerpolicy") this.referrerPolicy = "";
    if (attr === "kind") this.kind = "";
    if (attr === "srclang") this.srcLang = "";
    if (attr === "autocomplete") this.autocomplete = "";
    if (attr === "accept-charset") this.acceptCharset = "";
    if (attr === "enctype") this.enctype = "";
    if (attr === "method") this.method = "";
    if (attr === "target") this.target = "";
    if (attr === "formaction") this.formAction = "";
    if (attr === "formenctype") this.formEnctype = "";
    if (attr === "formmethod") this.formMethod = "";
    if (attr === "formtarget") this.formTarget = "";
    if (attr === "checked") this.checked = false;
    if (attr === "selected") this.selected = false;
    if (attr === "multiple") this.multiple = false;
    if (attr === "disabled") this.disabled = false;
    if (attr === "readonly") this.readOnly = false;
    if (attr === "required") this.required = false;
    if (attr === "open") this.open = false;
    if (attr === "hidden") this.hidden = false;
    if (attr === "inert") this.inert = false;
    if (attr === "draggable") this.draggable = false;
    if (attr === "controls") this.controls = false;
    if (attr === "muted") this.muted = false;
    if (attr === "loop") this.loop = false;
    if (attr === "autoplay") this.autoplay = false;
    if (attr === "playsinline") this.playsInline = false;
    if (attr === "disablePictureInPicture") this.disablePictureInPicture = false;
    if (attr === "disableRemotePlayback") this.disableRemotePlayback = false;
    if (attr === "novalidate") this.noValidate = false;
    if (attr === "formnovalidate") this.formNoValidate = false;
    if (attr === "ismap") this.isMap = false;
    if (attr === "reversed") this.reversed = false;
    if (attr === "default") this.default = false;
    if (attr === "class") {
      this.className = "";
      this.classList.items.clear();
    }
  }

  addEventListener(type, listener, options = undefined) {
    const key = String(type);
    const list = this.listeners.get(key) ?? [];
    const capture = typeof options === "boolean" ? options : Boolean(options?.capture);
    list.push({ listener, capture });
    this.listeners.set(key, list);
  }

  removeEventListener(type, listener, options = undefined) {
    const key = String(type);
    const list = this.listeners.get(key) ?? [];
    const capture = typeof options === "boolean" ? options : Boolean(options?.capture);
    this.listeners.set(key, list.filter((item) => item.listener !== listener || item.capture !== capture));
  }

  dispatchEvent(event) {
    const evt = typeof event === "string" ? { type: event } : event;
    if (!evt.target) evt.target = this;
    if (evt.defaultPrevented === undefined) evt.defaultPrevented = false;
    if (evt.cancelBubble === undefined) evt.cancelBubble = false;
    if (typeof evt.preventDefault !== "function") {
      evt.preventDefault = () => {
        evt.defaultPrevented = true;
      };
    }
    if (typeof evt.stopPropagation !== "function") {
      evt.stopPropagation = () => {
        evt.cancelBubble = true;
      };
    }
    const type = evt.type;
    const path = [];
    for (let node = this; node; node = node.parentNode) path.push(node);
    const invoke = (node, capture) => {
      const listeners = node.listeners.get(type) ?? [];
      for (const binding of listeners) {
        if (binding.capture !== capture) continue;
        evt.currentTarget = node;
        binding.listener(evt);
        if (evt.cancelBubble) return false;
      }
      return true;
    };
    for (const node of path.slice().reverse()) {
      if (!invoke(node, true)) return !evt.defaultPrevented;
    }
    for (const node of path) {
      if (!invoke(node, false)) return !evt.defaultPrevented;
    }
    return !evt.defaultPrevented;
  }
}

class TextNode {
  constructor(text) {
    this.tagName = "#text";
    this.children = [];
    this.parentNode = null;
    this.textContent = String(text ?? "");
    this.classList = { contains: () => false };
  }

  getAttribute(_key) {
    return null;
  }

  remove() {
    if (this.parentNode) this.parentNode.removeChild(this);
  }
}

class DocumentStub {
  constructor() {
    this.readyState = "loading";
    this.app = new Element("div");
    this.app.setAttribute("id", "app");
    this.activeElement = null;
  }

  createElement(tagName) {
    return new Element(tagName);
  }

  createElementNS(_namespace, tagName) {
    return new Element(tagName);
  }

  createTextNode(text) {
    return new TextNode(text);
  }

  createDocumentFragment() {
    return new Element("fragment");
  }

  querySelector(selector) {
    if (selector === "#app") return this.app;
    return findFirst(this.app, (node) => matchesSelector(node, selector));
  }

  querySelectorAll(selector) {
    return findAll(this.app, (node) => matchesSelector(node, selector));
  }
}

class WindowStub {
  constructor(document) {
    this.document = document;
    this.listeners = new Map();
  }

  addEventListener(type, listener) {
    const key = String(type);
    const list = this.listeners.get(key) ?? [];
    list.push(listener);
    this.listeners.set(key, list);
  }

  dispatchEvent(event) {
    const type = typeof event === "string" ? event : event.type;
    for (const listener of this.listeners.get(type) ?? []) {
      listener(event);
    }
  }
}

function matchesSelector(node, selector) {
  if (selector.startsWith("#")) return node.getAttribute("id") === selector.slice(1);
  if (selector.startsWith(".")) return node.classList.contains(selector.slice(1));
  return node.tagName === selector.toLowerCase();
}

function findAll(root, predicate) {
  const out = [];
  const visit = (node) => {
    if (predicate(node)) out.push(node);
    for (const child of node.children) visit(child);
  };
  visit(root);
  return out;
}

function findFirst(root, predicate) {
  return findAll(root, predicate)[0] ?? null;
}

function textOf(node) {
  return `${node.textContent}${node.children.map(textOf).join("")}`;
}

function optionValue(option) {
  return option.value || option.getAttribute("value") || textOf(option);
}

function textSnapshot(root) {
  return textOf(root).replace(/\s+/g, " ").trim();
}

function findButton(root, label) {
  const button = findAll(root, (node) => node.tagName === "button").find((node) => textOf(node) === label);
  if (!button) throw new Error(`missing button '${label}' in DOM: ${textSnapshot(root)}`);
  return button;
}

function findInput(root, index = 0) {
  const matches = findAll(root, (node) => node.tagName === "input");
  const node = matches[index];
  if (!node) throw new Error(`missing <input>[${index}] in DOM: ${textSnapshot(root)}`);
  return node;
}

function findTextByTag(root, tagName, index = 0) {
  const matches = findAll(root, (node) => node.tagName === tagName.toLowerCase());
  const node = matches[index];
  if (!node) throw new Error(`missing <${tagName}>[${index}] in DOM: ${textSnapshot(root)}`);
  return textOf(node);
}

function expectText(root, expected) {
  const text = textSnapshot(root);
  if (!text.includes(expected)) {
    throw new Error(`expected DOM text '${expected}', got '${text}'`);
  }
}

function expectTagText(root, tagName, index, expected) {
  const actual = findTextByTag(root, tagName, index);
  if (actual !== expected) {
    throw new Error(`expected <${tagName}>[${index}] text '${expected}', got '${actual}'`);
  }
}

async function waitFor(predicate, description) {
  for (let i = 0; i < 100; i += 1) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error(`timeout waiting for ${description}`);
}

async function boot(outDir) {
  const bootErrors = [];
  const originalConsoleError = console.error;
  console.error = (...args) => {
    bootErrors.push(args.map((arg) => (arg instanceof Error ? arg.stack : String(arg))).join(" "));
    originalConsoleError(...args);
  };

  const document = new DocumentStub();
  const window = new WindowStub(document);
  globalThis.document = document;
  globalThis.window = window;
  globalThis.location = { pathname: "/", search: "", hash: "" };
  globalThis.history = {
    pushState(_state, _title, url) {
      globalThis.location.pathname = String(url);
    },
    replaceState(_state, _title, url) {
      globalThis.location.pathname = String(url);
    },
  };
  globalThis.XMLHttpRequest = class {
    open() {}
    send() {
      this.status = 501;
      this.responseText = "";
    }
  };
  globalThis.fetch = async (url) => {
    const fileName = String(url).replace(/^\.\//, "");
    const bytes = await readFile(path.join(outDir, fileName));
    return new Response(bytes, { headers: { "Content-Type": "application/wasm" } });
  };

  const airlockSource = await readFile(path.join(outDir, "airlock.js"), "utf8");
  const moduleUrl = `data:text/javascript;base64,${Buffer.from(airlockSource).toString("base64")}#runtime=${Date.now()}`;
  const airlockModule = await import(moduleUrl);
  document.readyState = "complete";
  window.dispatchEvent({ type: "DOMContentLoaded" });
  try {
    await waitFor(() => document.app.children.length > 0 || bootErrors.length !== 0, "SAX app mount");
    if (bootErrors.length !== 0) {
      throw new Error(`SAX boot failed: ${bootErrors.join("\n")}`);
    }
    return { root: document.app, document, airlockModule };
  } finally {
    console.error = originalConsoleError;
  }
}

async function verifyDashboard(outDir) {
  const { root, document } = await boot(outDir);
  expectText(root, "SAX Ops Dashboard");
  expectText(root, "12");
  expectText(root, "2");
  expectText(root, "180 ms");

  findButton(root, "Record visit").dispatchEvent({ type: "click" });
  expectText(root, "13");

  findButton(root, "Ack alert").dispatchEvent({ type: "click" });
  expectText(root, "1");

  findButton(root, "Improve").dispatchEvent({ type: "click" });
  expectText(root, "170 ms");
}

async function verifyTyped(outDir) {
  const { root } = await boot(outDir);
  expectText(root, "Score: 7");
  expectText(root, "Active: 0");
  expectText(root, "Ratio: 0.750000");

  findButton(root, "Bump").dispatchEvent({ type: "click" });
  expectText(root, "Score: 8");
  expectText(root, "Active: 1");
  expectText(root, "Ratio: 0.750000");
}

async function verifyComposition(outDir) {
  const { root } = await boot(outDir);
  expectText(root, "React-style Layout: Composition");
  expectText(root, "Composition Demo");
  expectText(root, "Projected count: 0");
  expectText(root, "Layout ref seen: 1");
  expectText(root, "Button ref seen: 1");
  expectText(root, "Badge count: 0");
  expectText(root, "Direct projected count: 0");
  expectText(root, "Object config: {\"0\":0,\"1\":false,\"2\":false,\"4\":false,\"5\":0,\"9\":false,\"100\":false,\"title\":\"\",\"\":0,\"false\":0,\"true\":0,\"null\":0,\"0.500000\":0,\"0.250000\":0,\"disabled\":0,\"idle_branch\":true,\"idle_and_branch\":true,\"idle_or_branch\":true,\"status\":\"\",\"label\":\"\",\"nullable\":null,\"score\":9,\"bonus\":0,\"rating\":2,\"rating_floor\":4,\"visible\":false,\"pinned\":false,\"precision\":0.5,\"precision_floor\":0.25,\"spread_idle\":0,\"spread\":\"static\",\"spread_count\":0,\"count\":0,\"active\":false,\"tags\":[\"alpha\",\"\",0,false],\"variants\":[\"\",9,0,2,4,false,true,\"\",0.5,0.25,\"\"],\"computed_items\":[{\"9\":false,\"size\":1,\"item_idle\":0,\"\":0,\"current\":0}],\"leading_computed_items\":[{\"9\":false,\"leading_item_idle\":0,\"\":0,\"current\":0}],\"items\":[{\"200\":false,\"size\":1,\"current\":0,\"idle_item\":true,\"idle_item_or\":true,\"nested_spread_idle\":0,\"false\":0,\"enabled\":true,\"spread_active\":false}],\"and_ptr_items\":[{\"size\":1,\"current\":0}],\"leading_items\":[{\"current\":0,\"enabled\":true,\"spread_active\":false}],\"leading_static_spread_items\":[{\"300\":false,\"leading_spread_idle\":0,\"false\":0,\"enabled\":true,\"spread_active\":false,\"current\":0}],\"leading_conditional_items\":[{\"idle_leading_item\":true,\"current\":0}],\"leading_active_items\":[{\"current\":0}],\"leading_ptr_and_items\":[{\"current\":0}],\"leading_negated_ptr_and_items\":[{\"current\":0}],\"leading_null_items\":[{\"current\":0}],\"leading_ptr_null_items\":[{\"current\":0}],\"leading_ptr_fallback_items\":[{\"idle_ptr_fallback\":true,\"current\":0}],\"leading_ptr_branch_items\":[{\"current\":0}],\"leading_or_items\":[{\"idle_leading_or\":true,\"current\":0}],\"leading_ptr_or_items\":[{\"current\":0}],\"leading_negated_or_items\":[{\"current\":0}],\"leading_negated_ptr_or_items\":[{\"current\":0}],\"leading_static_spread_nested\":{\"400\":false,\"leading_nested_spread_idle\":0,\"false\":0,\"enabled\":true,\"spread_active\":false,\"current\":0},\"ternary_static_spread_items\":[{\"false\":9,\"true\":0,\"current\":0}],\"leading_nested\":{\"9\":false,\"leading_nested_idle\":0,\"\":0,\"current\":0},\"nested\":{\"9\":false,\"200\":false,\"size\":2,\"idle_nested_branch\":true,\"idle_nested_and\":true,\"idle_nested_or\":true,\"nested_idle\":0,\"\":0,\"current\":0,\"nested_spread_idle\":0,\"false\":0,\"enabled\":true,\"spread_active\":false}}");

  const extraInput = findInput(root, 0);
  extraInput.value = '{"title":"spread-title","count":99,"tags":["from-spread"],"extra":"spread"}';
  extraInput.dispatchEvent({ type: "input" });
  expectText(root, "Object config: {\"0\":0,\"1\":false,\"2\":false,\"4\":false,\"5\":0,\"9\":false,\"100\":false,\"title\":\"\",\"count\":0,\"tags\":[\"alpha\",\"\",0,false],\"extra\":\"spread\",\"\":0,\"false\":0,\"true\":0,\"null\":0,\"0.500000\":0,\"0.250000\":0,\"disabled\":0,\"idle_branch\":true,\"idle_and_branch\":true,\"idle_or_branch\":true,\"status\":\"\",\"label\":\"\",\"nullable\":null,\"score\":9,\"bonus\":0,\"rating\":2,\"rating_floor\":4,\"visible\":false,\"pinned\":false,\"precision\":0.5,\"precision_floor\":0.25,\"spread_idle\":0,\"spread\":\"static\",\"spread_count\":0,\"active\":false,\"variants\":[\"\",9,0,2,4,false,true,\"\",0.5,0.25,\"\"],\"computed_items\":[{\"9\":false,\"size\":1,\"item_idle\":0,\"\":0,\"current\":0}],\"leading_computed_items\":[{\"9\":false,\"leading_item_idle\":0,\"\":0,\"current\":0}],\"items\":[{\"200\":false,\"size\":1,\"current\":0,\"idle_item\":true,\"idle_item_or\":true,\"nested_spread_idle\":0,\"false\":0,\"enabled\":true,\"spread_active\":false}],\"and_ptr_items\":[{\"size\":1,\"current\":0}],\"leading_items\":[{\"current\":0,\"enabled\":true,\"spread_active\":false}],\"leading_static_spread_items\":[{\"300\":false,\"leading_spread_idle\":0,\"false\":0,\"enabled\":true,\"spread_active\":false,\"current\":0}],\"leading_conditional_items\":[{\"idle_leading_item\":true,\"current\":0}],\"leading_active_items\":[{\"current\":0}],\"leading_ptr_and_items\":[{\"current\":0}],\"leading_negated_ptr_and_items\":[{\"current\":0}],\"leading_null_items\":[{\"current\":0}],\"leading_ptr_null_items\":[{\"current\":0}],\"leading_ptr_fallback_items\":[{\"idle_ptr_fallback\":true,\"current\":0}],\"leading_ptr_branch_items\":[{\"current\":0}],\"leading_or_items\":[{\"idle_leading_or\":true,\"current\":0}],\"leading_ptr_or_items\":[{\"current\":0}],\"leading_negated_or_items\":[{\"current\":0}],\"leading_negated_ptr_or_items\":[{\"current\":0}],\"leading_static_spread_nested\":{\"400\":false,\"leading_nested_spread_idle\":0,\"false\":0,\"enabled\":true,\"spread_active\":false,\"current\":0},\"ternary_static_spread_items\":[{\"false\":9,\"true\":0,\"current\":0}],\"leading_nested\":{\"9\":false,\"leading_nested_idle\":0,\"\":0,\"current\":0},\"nested\":{\"9\":false,\"200\":false,\"size\":2,\"idle_nested_branch\":true,\"idle_nested_and\":true,\"idle_nested_or\":true,\"nested_idle\":0,\"\":0,\"current\":0,\"nested_spread_idle\":0,\"false\":0,\"enabled\":true,\"spread_active\":false}}");

  const statusInput = findInput(root, 2);
  statusInput.value = 'idle';
  statusInput.dispatchEvent({ type: "input" });
  expectText(root, "Object config: {\"0\":0,\"1\":false,\"2\":false,\"4\":false,\"5\":0,\"9\":false,\"100\":false,\"title\":\"\",\"count\":0,\"tags\":[\"alpha\",\"\",0,false],\"extra\":\"spread\",\"\":0,\"false\":0,\"true\":0,\"null\":0,\"0.500000\":0,\"0.250000\":0,\"disabled\":0,\"idle\":0,\"idle_branch\":true,\"idle_and_branch\":true,\"idle_or_branch\":true,\"status\":\"idle\",\"label\":\"idle\",\"nullable\":null,\"score\":9,\"bonus\":0,\"rating\":2,\"rating_floor\":4,\"visible\":false,\"pinned\":false,\"precision\":0.5,\"precision_floor\":0.25,\"spread_idle\":0,\"spread\":\"static\",\"spread_count\":0,\"active\":false,\"variants\":[\"idle\",9,0,2,4,false,true,\"idle\",0.5,0.25,\"idle\"],\"computed_items\":[{\"9\":false,\"size\":1,\"item_idle\":0,\"idle\":0,\"current\":0}],\"leading_computed_items\":[{\"9\":false,\"leading_item_idle\":0,\"idle\":0,\"current\":0}],\"items\":[{\"200\":false,\"size\":1,\"current\":0,\"idle_item\":true,\"idle_item_or\":true,\"nested_spread_idle\":0,\"false\":0,\"enabled\":true,\"spread_active\":false}],\"and_ptr_items\":[{\"size\":1,\"current\":0}],\"leading_items\":[{\"current\":0,\"enabled\":true,\"spread_active\":false}],\"leading_static_spread_items\":[{\"300\":false,\"leading_spread_idle\":0,\"false\":0,\"enabled\":true,\"spread_active\":false,\"current\":0}],\"leading_conditional_items\":[{\"idle_leading_item\":true,\"current\":0}],\"leading_active_items\":[{\"current\":0}],\"leading_ptr_and_items\":[{\"current\":0}],\"leading_negated_ptr_and_items\":[{\"current\":0}],\"leading_null_items\":[{\"current\":0}],\"leading_ptr_null_items\":[{\"current\":0}],\"leading_ptr_fallback_items\":[{\"idle_ptr_fallback\":true,\"current\":0}],\"leading_ptr_branch_items\":[{\"current\":0}],\"leading_or_items\":[{\"idle_leading_or\":true,\"current\":0}],\"leading_ptr_or_items\":[{\"current\":0}],\"leading_negated_or_items\":[{\"current\":0}],\"leading_negated_ptr_or_items\":[{\"current\":0}],\"leading_static_spread_nested\":{\"400\":false,\"leading_nested_spread_idle\":0,\"false\":0,\"enabled\":true,\"spread_active\":false,\"current\":0},\"ternary_static_spread_items\":[{\"false\":9,\"true\":0,\"current\":0}],\"leading_nested\":{\"9\":false,\"leading_nested_idle\":0,\"idle\":0,\"current\":0},\"nested\":{\"9\":false,\"200\":false,\"size\":2,\"idle_nested_branch\":true,\"idle_nested_and\":true,\"idle_nested_or\":true,\"nested_idle\":0,\"idle\":0,\"current\":0,\"nested_spread_idle\":0,\"false\":0,\"enabled\":true,\"spread_active\":false}}");

  const nestedInput = findInput(root, 3);
  nestedInput.value = '{"current":44,"enabled":false,"from_nested":"spread"}';
  nestedInput.dispatchEvent({ type: "input" });
  expectText(root, "Object config: {\"0\":0,\"1\":false,\"2\":false,\"4\":false,\"5\":0,\"9\":false,\"100\":false,\"title\":\"\",\"count\":0,\"tags\":[\"alpha\",\"\",0,false],\"extra\":\"spread\",\"\":0,\"false\":0,\"true\":0,\"null\":0,\"0.500000\":0,\"0.250000\":0,\"disabled\":0,\"idle\":0,\"idle_branch\":true,\"idle_and_branch\":true,\"idle_or_branch\":true,\"current\":44,\"enabled\":false,\"from_nested\":\"spread\",\"status\":\"idle\",\"label\":\"idle\",\"nullable\":null,\"score\":9,\"bonus\":0,\"rating\":2,\"rating_floor\":4,\"visible\":false,\"pinned\":false,\"precision\":0.5,\"precision_floor\":0.25,\"spread_idle\":0,\"spread\":\"static\",\"spread_count\":0,\"active\":false,\"variants\":[\"idle\",9,0,2,4,false,true,\"idle\",0.5,0.25,\"idle\"],\"computed_items\":[{\"9\":false,\"size\":1,\"item_idle\":0,\"idle\":0,\"current\":0}],\"leading_computed_items\":[{\"9\":false,\"leading_item_idle\":0,\"idle\":0,\"current\":0}],\"items\":[{\"200\":false,\"size\":1,\"current\":0,\"enabled\":true,\"from_nested\":\"spread\",\"idle_item\":true,\"idle_item_or\":true,\"nested_spread_idle\":0,\"false\":0,\"spread_active\":false}],\"and_ptr_items\":[{\"size\":1,\"current\":0}],\"leading_items\":[{\"current\":0,\"enabled\":true,\"from_nested\":\"spread\",\"spread_active\":false}],\"leading_static_spread_items\":[{\"300\":false,\"leading_spread_idle\":0,\"false\":0,\"enabled\":true,\"spread_active\":false,\"current\":0}],\"leading_conditional_items\":[{\"idle_leading_item\":true,\"current\":0}],\"leading_active_items\":[{\"current\":0}],\"leading_ptr_and_items\":[{\"current\":0}],\"leading_negated_ptr_and_items\":[{\"current\":0,\"enabled\":false,\"from_nested\":\"spread\"}],\"leading_null_items\":[{\"current\":0}],\"leading_ptr_null_items\":[{\"current\":0}],\"leading_ptr_fallback_items\":[{\"idle_ptr_fallback\":true,\"current\":0}],\"leading_ptr_branch_items\":[{\"current\":0}],\"leading_or_items\":[{\"idle_leading_or\":true,\"current\":0}],\"leading_ptr_or_items\":[{\"current\":0,\"enabled\":false,\"from_nested\":\"spread\"}],\"leading_negated_or_items\":[{\"current\":0}],\"leading_negated_ptr_or_items\":[{\"current\":0}],\"leading_static_spread_nested\":{\"400\":false,\"leading_nested_spread_idle\":0,\"false\":0,\"enabled\":true,\"spread_active\":false,\"current\":0},\"ternary_static_spread_items\":[{\"false\":9,\"true\":0,\"current\":0}],\"leading_nested\":{\"9\":false,\"leading_nested_idle\":0,\"idle\":0,\"current\":0},\"nested\":{\"9\":false,\"200\":false,\"size\":2,\"idle_nested_branch\":true,\"current\":0,\"enabled\":true,\"from_nested\":\"spread\",\"idle_nested_and\":true,\"idle_nested_or\":true,\"nested_idle\":0,\"idle\":0,\"nested_spread_idle\":0,\"false\":0,\"spread_active\":false}}");

  const branchInput = findInput(root, 1);
  branchInput.value = '{"branch":"on","count":77,"active":false}';
  branchInput.dispatchEvent({ type: "input" });
  expectText(root, "Object config: {\"0\":0,\"1\":false,\"2\":false,\"4\":false,\"5\":0,\"9\":false,\"100\":false,\"title\":\"\",\"count\":0,\"tags\":[\"alpha\",\"\",0,false],\"extra\":\"spread\",\"\":0,\"false\":0,\"true\":0,\"null\":0,\"0.500000\":0,\"0.250000\":0,\"disabled\":0,\"idle\":0,\"idle_branch\":true,\"branch\":\"on\",\"active\":false,\"idle_and_branch\":true,\"idle_or_branch\":true,\"current\":44,\"enabled\":false,\"from_nested\":\"spread\",\"status\":\"idle\",\"label\":\"idle\",\"nullable\":null,\"score\":9,\"bonus\":0,\"rating\":2,\"rating_floor\":4,\"visible\":false,\"pinned\":false,\"precision\":0.5,\"precision_floor\":0.25,\"spread_idle\":0,\"spread\":\"static\",\"spread_count\":0,\"variants\":[\"idle\",9,0,2,4,false,true,\"idle\",0.5,0.25,\"idle\"],\"computed_items\":[{\"9\":false,\"size\":1,\"item_idle\":0,\"idle\":0,\"current\":0}],\"leading_computed_items\":[{\"9\":false,\"leading_item_idle\":0,\"idle\":0,\"current\":0}],\"items\":[{\"200\":false,\"size\":1,\"current\":0,\"enabled\":true,\"from_nested\":\"spread\",\"idle_item\":true,\"idle_item_or\":true,\"branch\":\"on\",\"count\":77,\"active\":false,\"nested_spread_idle\":0,\"false\":0,\"spread_active\":false}],\"and_ptr_items\":[{\"size\":1,\"branch\":\"on\",\"count\":77,\"active\":false,\"current\":0}],\"leading_items\":[{\"current\":0,\"enabled\":true,\"from_nested\":\"spread\",\"spread_active\":false}],\"leading_static_spread_items\":[{\"300\":false,\"leading_spread_idle\":0,\"false\":0,\"enabled\":true,\"spread_active\":false,\"current\":0}],\"leading_conditional_items\":[{\"idle_leading_item\":true,\"current\":0}],\"leading_active_items\":[{\"current\":0}],\"leading_ptr_and_items\":[{\"current\":0}],\"leading_negated_ptr_and_items\":[{\"current\":0,\"enabled\":false,\"from_nested\":\"spread\"}],\"leading_null_items\":[{\"current\":0}],\"leading_ptr_null_items\":[{\"current\":0}],\"leading_ptr_fallback_items\":[{\"idle_ptr_fallback\":true,\"current\":0}],\"leading_ptr_branch_items\":[{\"branch\":\"on\",\"count\":77,\"active\":false,\"current\":0}],\"leading_or_items\":[{\"idle_leading_or\":true,\"current\":0}],\"leading_ptr_or_items\":[{\"current\":0,\"enabled\":false,\"from_nested\":\"spread\"}],\"leading_negated_or_items\":[{\"current\":0}],\"leading_negated_ptr_or_items\":[{\"current\":0}],\"leading_static_spread_nested\":{\"400\":false,\"leading_nested_spread_idle\":0,\"false\":0,\"enabled\":true,\"spread_active\":false,\"current\":0},\"ternary_static_spread_items\":[{\"false\":9,\"true\":0,\"current\":0}],\"leading_nested\":{\"9\":false,\"leading_nested_idle\":0,\"idle\":0,\"current\":0},\"nested\":{\"9\":false,\"200\":false,\"size\":2,\"idle_nested_branch\":true,\"branch\":\"on\",\"count\":77,\"active\":false,\"current\":0,\"enabled\":true,\"from_nested\":\"spread\",\"idle_nested_and\":true,\"idle_nested_or\":true,\"nested_idle\":0,\"idle\":0,\"nested_spread_idle\":0,\"false\":0,\"spread_active\":false}}");

  const layout = findAll(root, (node) => node.tagName === "article" && node.classList.contains("layout-shell"))[0];
  if (!layout) throw new Error(`missing layout shell in DOM: ${textSnapshot(root)}`);
  const slot = findAll(layout, (node) => node.tagName === "slot")[0];
  if (!slot) throw new Error(`missing projected slot in layout DOM: ${textSnapshot(root)}`);
  if (!textSnapshot(slot).includes("Projected count: 0")) {
    throw new Error(`expected projected children inside slot, got '${textSnapshot(slot)}'`);
  }

  findButton(root, "Increment projected count").dispatchEvent({ type: "click" });
  expectText(root, "Projected count: 1");
  expectText(root, "Layout ref seen: 1");
  expectText(root, "Button ref seen: 1");
  expectText(root, "Badge count: 1");
  expectText(root, "Direct projected count: 1");
  expectText(root, "Object config: {\"1\":1,\"2\":true,\"3\":true,\"8\":1,\"101\":true,\"title\":\"click\",\"count\":1,\"tags\":[\"alpha\",\"click\",1,true],\"extra\":\"spread\",\"click\":1,\"true\":1,\"false\":1,\"idle\":1,\"0.750000\":1,\"enabled\":false,\"ready\":1,\"branch\":\"on\",\"active\":true,\"active_null_branch\":true,\"current\":44,\"from_nested\":\"spread\",\"active_and_branch\":true,\"active_or_branch\":true,\"status\":\"click\",\"label\":\"ready\",\"nullable\":\"click\",\"score\":1,\"bonus\":1,\"rating\":3,\"rating_floor\":3,\"visible\":true,\"pinned\":true,\"precision\":0.75,\"precision_floor\":0.75,\"spread_ready\":1,\"spread\":\"static\",\"spread_count\":1,\"variants\":[\"click\",1,1,3,3,true,false,null,0.75,0.75,\"ready\"],\"computed_items\":[{\"1\":true,\"size\":1,\"item_ready\":1,\"click\":1,\"current\":1}],\"leading_computed_items\":[{\"1\":true,\"leading_item_ready\":1,\"click\":1,\"current\":1}],\"items\":[{\"201\":true,\"size\":1,\"current\":1,\"enabled\":true,\"from_nested\":\"spread\",\"active_item\":true,\"active_item_branch\":true,\"active_item_or\":true,\"branch\":\"on\",\"count\":77,\"active\":false,\"nested_spread_ready\":1,\"true\":1,\"spread_active\":true}],\"and_ptr_items\":[{\"size\":1,\"branch\":\"on\",\"count\":77,\"active\":false,\"current\":1}],\"leading_items\":[{\"current\":1,\"enabled\":true,\"from_nested\":\"spread\",\"spread_active\":true}],\"leading_static_spread_items\":[{\"301\":true,\"leading_spread_ready\":1,\"true\":1,\"enabled\":true,\"spread_active\":true,\"current\":1}],\"leading_conditional_items\":[{\"current\":1}],\"leading_active_items\":[{\"active_leading_item\":true,\"current\":1}],\"leading_ptr_and_items\":[{\"current\":1,\"enabled\":false,\"from_nested\":\"spread\"}],\"leading_negated_ptr_and_items\":[{\"current\":1}],\"leading_null_items\":[{\"active_leading_branch\":true,\"current\":1}],\"leading_ptr_null_items\":[{\"current\":1,\"enabled\":false,\"from_nested\":\"spread\"}],\"leading_ptr_fallback_items\":[{\"current\":1,\"enabled\":false,\"from_nested\":\"spread\"}],\"leading_ptr_branch_items\":[{\"current\":1,\"enabled\":false,\"from_nested\":\"spread\"}],\"leading_or_items\":[{\"current\":1}],\"leading_ptr_or_items\":[{\"current\":1}],\"leading_negated_or_items\":[{\"active_leading_or\":true,\"current\":1}],\"leading_negated_ptr_or_items\":[{\"current\":1,\"enabled\":false,\"from_nested\":\"spread\"}],\"leading_static_spread_nested\":{\"401\":true,\"leading_nested_spread_ready\":1,\"true\":1,\"enabled\":true,\"spread_active\":true,\"current\":1},\"ternary_static_spread_items\":[{\"true\":9,\"false\":1,\"current\":1}],\"leading_nested\":{\"1\":true,\"leading_nested_ready\":1,\"click\":1,\"current\":1},\"nested\":{\"1\":true,\"201\":true,\"size\":2,\"current\":1,\"enabled\":true,\"from_nested\":\"spread\",\"active_nested_branch\":true,\"active_nested_and\":true,\"active_nested_or\":true,\"branch\":\"on\",\"count\":77,\"active\":false,\"nested_ready\":1,\"click\":1,\"nested_spread_ready\":1,\"true\":1,\"spread_active\":true}}");
}

async function verifyComponentEvents(outDir) {
  const { root } = await boot(outDir);
  expectText(root, "Component Events");
  expectText(root, "Clicks: 0");
  expectText(root, "Changes: 0");

  findButton(root, "Forwarded button").dispatchEvent({ type: "click" });
  expectText(root, "Clicks: 1");

  const input = findInput(root);
  input.value = "typed";
  input.dispatchEvent({ type: "input" });
  expectText(root, "Changes: 1");
  input.dispatchEvent({ type: "change" });
  expectText(root, "Changes: 1");
}

async function verifyDomSurface(outDir) {
  const { root } = await boot(outDir);
  expectText(root, "Native controls");
  expectText(root, "Range value: 50");
  expectText(root, "Double clicks: 0");
  expectText(root, "Captured: 0");
  expectText(root, "Bubbled: 0");
  expectText(root, "Mouse enters: 0");
  expectText(root, "Mouse leave captures: 0");
  expectText(root, "Selected values:");
  expectText(root, "Scrolls: 0");
  expectText(root, "Toggles: 0");
  expectText(root, "Before inputs: 0");
  expectText(root, "Before input data:");
  expectText(root, "Before input type:");
  expectText(root, "Related target: 0");
  expectText(root, "Related target name:");
  expectText(root, "Related target id:");
  expectText(root, "Key:");
  expectText(root, "Code:");
  expectText(root, "Repeat: 0");
  expectText(root, "Pointer id: 0");
  expectText(root, "Pointer type:");
  expectText(root, "Pointer primary: 0");
  expectText(root, "Wheel delta: 0,0,0");
  expectText(root, "Wheel mode: 0");
  expectText(root, "Touches: 0");
  expectText(root, "Touch id: 0");
  expectText(root, "Touch client: 0,0");
  expectText(root, "Clipboard text:");
  expectText(root, "Drop text:");

  const surface = findAll(root, (node) => node.tagName === "main")[0];
  if (!surface) throw new Error(`missing surface main in DOM: ${textSnapshot(root)}`);
  if (surface.className !== "surface" || surface.getAttribute("class") !== "surface" || !surface.classList.contains("surface")) {
    throw new Error("expected className to set DOM property, class attribute, and classList token");
  }

  const dialog = findAll(root, (node) => node.tagName === "dialog")[0];
  if (!dialog) throw new Error(`missing dialog in DOM: ${textSnapshot(root)}`);
  if (dialog.open !== true) {
    throw new Error("expected dialog open property to be true");
  }
  if (dialog.getAttribute("aria-label") !== "React DOM surface") {
    throw new Error(`dialog aria-label was '${dialog.getAttribute("aria-label")}'`);
  }

  const details = findAll(root, (node) => node.tagName === "details")[0];
  if (!details) throw new Error(`missing details in DOM: ${textSnapshot(root)}`);
  if (details.open !== true) {
    throw new Error("expected details open property to be true");
  }

  const meter = findAll(root, (node) => node.tagName === "meter")[0];
  if (!meter) throw new Error(`missing meter in DOM: ${textSnapshot(root)}`);
  if (meter.min !== "0" || meter.max !== "100" || meter.low !== "25" || meter.high !== "80" || meter.optimum !== "60" || meter.value !== "50") {
    throw new Error("expected meter constraint props to set DOM properties");
  }
  if (meter.getAttribute("min") !== "0" || meter.getAttribute("max") !== "100" || meter.getAttribute("low") !== "25" || meter.getAttribute("high") !== "80" || meter.getAttribute("optimum") !== "60" || meter.getAttribute("value") !== "50") {
    throw new Error("expected meter constraint props to remain reflected as attributes");
  }

  const progress = findAll(root, (node) => node.tagName === "progress")[0];
  if (!progress) throw new Error(`missing progress in DOM: ${textSnapshot(root)}`);
  if (progress.max !== "100" || progress.value !== "35") {
    throw new Error("expected progress value/max props to set DOM properties");
  }
  if (progress.getAttribute("max") !== "100" || progress.getAttribute("value") !== "35") {
    throw new Error("expected progress value/max props to remain reflected as attributes");
  }

  const range = findAll(root, (node) => node.tagName === "input" && node.getAttribute("type") === "range")[0];
  if (!range) throw new Error(`missing range input in DOM: ${textSnapshot(root)}`);
  if (range.min !== "0") throw new Error(`expected range min property=0, got '${range.min}'`);
  if (range.max !== "100") throw new Error(`expected range max property=100, got '${range.max}'`);
  if (range.step !== "5") throw new Error(`expected range step property=5, got '${range.step}'`);
  if (range.getAttribute("min") !== "0") throw new Error(`expected range min=0, got '${range.getAttribute("min")}'`);
  if (range.getAttribute("max") !== "100") throw new Error(`expected range max=100, got '${range.getAttribute("max")}'`);
  if (range.getAttribute("step") !== "5") throw new Error(`expected range step=5, got '${range.getAttribute("step")}'`);
  if (range.getAttribute("tabindex") !== "0") throw new Error(`expected normalized tabindex=0, got '${range.getAttribute("tabindex")}'`);
  if (range.tabIndex !== "0") throw new Error(`expected tabIndex property=0, got '${range.tabIndex}'`);
  if (range.inputMode !== "numeric") throw new Error(`expected range inputMode property=numeric, got '${range.inputMode}'`);
  if (range.enterKeyHint !== "done") throw new Error(`expected range enterKeyHint property=done, got '${range.enterKeyHint}'`);

  const trustedHtml = findAll(root, (node) => node.getAttribute("id") === "trusted-html")[0];
  if (!trustedHtml) throw new Error(`missing dangerouslySetInnerHTML node in DOM: ${textSnapshot(root)}`);
  if (trustedHtml.innerHTML !== "<strong>Trusted markup</strong>") {
    throw new Error(`expected trusted innerHTML to be written, got '${trustedHtml.innerHTML}'`);
  }
  if (range.autoCapitalize !== "none") throw new Error(`expected range autoCapitalize property=none, got '${range.autoCapitalize}'`);
  if (range.autocorrect !== "off") throw new Error(`expected range autocorrect property=off, got '${range.autocorrect}'`);
  if (range.getAttribute("inputmode") !== "numeric") throw new Error(`expected normalized inputmode=numeric, got '${range.getAttribute("inputmode")}'`);
  if (range.getAttribute("enterkeyhint") !== "done") throw new Error(`expected normalized enterkeyhint=done, got '${range.getAttribute("enterkeyhint")}'`);
  if (range.getAttribute("autocapitalize") !== "none") throw new Error(`expected normalized autocapitalize=none, got '${range.getAttribute("autocapitalize")}'`);
  if (range.getAttribute("autocorrect") !== "off") throw new Error(`expected normalized autocorrect=off, got '${range.getAttribute("autocorrect")}'`);
  if (document.activeElement !== range) {
    throw new Error("expected autoFocus range input to become document.activeElement after mount");
  }

  const beforeInput = findAll(root, (node) => node.tagName === "input" && node.value === "before")[0];
  if (!beforeInput) throw new Error(`missing beforeinput test input in DOM: ${textSnapshot(root)}`);
  beforeInput.dispatchEvent({ type: "beforeinput", data: "x", inputType: "insertText" });
  expectText(root, "Before inputs: 1");
  expectText(root, "Before input data: x");
  expectText(root, "Before input type: insertText");

  const pasteInput = findAll(root, (node) => node.tagName === "input" && node.value === "paste here")[0];
  if (!pasteInput) throw new Error(`missing paste test input in DOM: ${textSnapshot(root)}`);
  pasteInput.dispatchEvent({ type: "paste", clipboardData: { getData: (kind) => kind === "text" ? "clip text" : "" } });
  expectText(root, "Clipboard text: clip text");

  const keyboardInput = findAll(root, (node) => node.tagName === "input" && node.value === "keyboard")[0];
  if (!keyboardInput) throw new Error(`missing keyboard test input in DOM: ${textSnapshot(root)}`);
  if (keyboardInput.size !== "12" || keyboardInput.maxLength !== "24" || keyboardInput.minLength !== "3") {
    throw new Error("expected input size/maxLength/minLength props to set DOM properties");
  }
  if (keyboardInput.placeholder !== "Type keys" || keyboardInput.pattern !== "[A-Za-z]+" || keyboardInput.accept !== "text/plain" || keyboardInput.capture !== "environment" || keyboardInput.dirName !== "keyboard.dir") {
    throw new Error("expected input placeholder/pattern/accept/capture/dirName props to set DOM properties");
  }
  if (keyboardInput.autocomplete !== "username") {
    throw new Error(`expected input autocomplete property=username, got '${keyboardInput.autocomplete}'`);
  }
  if (keyboardInput.getAttribute("size") !== "12" || keyboardInput.getAttribute("maxlength") !== "24" || keyboardInput.getAttribute("minlength") !== "3") {
    throw new Error("expected input size/maxLength/minLength props to remain reflected as attributes");
  }
  if (keyboardInput.getAttribute("placeholder") !== "Type keys" || keyboardInput.getAttribute("pattern") !== "[A-Za-z]+" || keyboardInput.getAttribute("accept") !== "text/plain" || keyboardInput.getAttribute("capture") !== "environment" || keyboardInput.getAttribute("dirname") !== "keyboard.dir") {
    throw new Error("expected input placeholder/pattern/accept/capture/dirName props to remain reflected as attributes");
  }
  if (keyboardInput.getAttribute("autocomplete") !== "username") {
    throw new Error(`expected input autocomplete=username, got '${keyboardInput.getAttribute("autocomplete")}'`);
  }
  const keyboardLabel = findAll(root, (node) => node.tagName === "label" && textOf(node) === "Keyboard field")[0];
  if (!keyboardLabel) throw new Error(`missing keyboard label in DOM: ${textSnapshot(root)}`);
  if (keyboardLabel.htmlFor !== "keyboard-input" || keyboardLabel.getAttribute("for") !== "keyboard-input") {
    throw new Error("expected label htmlFor prop to set property and for attribute");
  }
  const keyboardOutput = findAll(root, (node) => node.tagName === "output" && textOf(node) === "Keyboard output")[0];
  if (!keyboardOutput) throw new Error(`missing keyboard output in DOM: ${textSnapshot(root)}`);
  if (keyboardOutput.htmlFor !== "keyboard-input" || keyboardOutput.getAttribute("for") !== "keyboard-input") {
    throw new Error("expected output htmlFor prop to set property and for attribute");
  }
  keyboardInput.dispatchEvent({ type: "keydown", key: "Enter", code: "Enter", repeat: true });
  expectText(root, "Key: Enter");
  expectText(root, "Code: Enter");
  expectText(root, "Repeat: 1");

  const options = findAll(root, (node) => node.tagName === "option");
  if (options.length < 2) throw new Error(`missing select options in DOM: ${textSnapshot(root)}`);
  if (options[0].label !== "Basic option" || options[0].getAttribute("label") !== "Basic option") {
    throw new Error("expected option label prop to set property and reflected attribute");
  }
  if (options[0].value !== "basic" || options[0].getAttribute("value") !== "basic") {
    throw new Error("expected option value prop to set property and reflected attribute");
  }
  if (options[1].label !== "Advanced option" || options[1].getAttribute("label") !== "Advanced option") {
    throw new Error("expected defaultSelected option label prop to set property and reflected attribute");
  }
  if (options[1].value !== "advanced" || options[1].getAttribute("value") !== "advanced") {
    throw new Error("expected defaultSelected option value prop to set property and reflected attribute");
  }
  if (options[0].selected !== false) throw new Error("expected first option to start unselected");
  if (options[1].selected !== true) throw new Error("expected second option defaultSelected to set selected property");
  options[1].selected = false;

  const selects = findAll(root, (node) => node.tagName === "select");
  if (selects.length < 2) throw new Error(`missing select controls in DOM: ${textSnapshot(root)}`);
  if (selects[0].autocomplete !== "country-name" || selects[0].getAttribute("autocomplete") !== "country-name") {
    throw new Error("expected select autoComplete prop to set property and reflected attribute");
  }
  if (selects[1].multiple !== true) throw new Error("expected second select multiple property to be true");
  if (selects[1].size !== "3" || selects[1].getAttribute("size") !== "3") {
    throw new Error("expected multiple select size prop to set property and attribute");
  }
  const multipleOptions = selects[1].options;
  if (multipleOptions.length !== 3) throw new Error(`expected three multiple-select options, got ${multipleOptions.length}`);
  if (multipleOptions[0].selected !== true || multipleOptions[1].selected !== true || multipleOptions[2].selected !== false) {
    throw new Error("expected multiple select value to select alpha,beta only");
  }
  if (selects[1].value !== "alpha,beta") {
    throw new Error(`expected multiple select value getter to return alpha,beta, got '${selects[1].value}'`);
  }
  multipleOptions[0].selected = false;
  multipleOptions[1].selected = true;
  multipleOptions[2].selected = true;
  selects[1].dispatchEvent({ type: "change" });
  expectText(root, "Selected values: beta,gamma");

  const defaultSingleSelect = selects[2];
  if (!defaultSingleSelect) throw new Error(`missing defaultValue single select in DOM: ${textSnapshot(root)}`);
  if (defaultSingleSelect.value !== "secondary") {
    throw new Error(`expected defaultValue single select to initialize value=secondary, got '${defaultSingleSelect.value}'`);
  }
  defaultSingleSelect.value = "primary";

  const optgroup = findAll(root, (node) => node.tagName === "optgroup")[0];
  if (!optgroup) throw new Error(`missing optgroup in DOM: ${textSnapshot(root)}`);
  if (optgroup.label !== "Grouped choices" || optgroup.getAttribute("label") !== "Grouped choices") {
    throw new Error("expected optgroup label prop to set property and reflected attribute");
  }
  const groupedOption = findAll(optgroup, (node) => node.tagName === "option")[0];
  if (!groupedOption || groupedOption.label !== "Grouped option" || groupedOption.getAttribute("label") !== "Grouped option") {
    throw new Error("expected grouped option label prop to set property and reflected attribute");
  }

  const defaultMultiSelect = selects[4];
  if (!defaultMultiSelect) throw new Error(`missing defaultValue multiple select in DOM: ${textSnapshot(root)}`);
  if (defaultMultiSelect.multiple !== true) throw new Error("expected defaultValue multiple select to set multiple property");
  const defaultMultiOptions = defaultMultiSelect.options;
  if (defaultMultiOptions[0].selected !== true || defaultMultiOptions[1].selected !== true || defaultMultiOptions[2].selected !== false) {
    throw new Error(`expected defaultValue multiple select to initialize delta,epsilon only, got ${defaultMultiOptions.map((option) => `${optionValue(option)}:${option.selected}`).join(",")}`);
  }
  defaultMultiOptions[0].selected = false;
  defaultMultiOptions[1].selected = false;
  defaultMultiOptions[2].selected = true;

  const textarea = findAll(root, (node) => node.tagName === "textarea")[0];
  if (!textarea) throw new Error(`missing textarea in DOM: ${textSnapshot(root)}`);
  if (textarea.value !== "Textarea default") {
    throw new Error(`expected textarea children to initialize value, got '${textarea.value}'`);
  }
  if (textarea.rows !== "4" || textarea.cols !== "24" || textarea.wrap !== "soft" || textarea.maxLength !== "80" || textarea.minLength !== "5" || textarea.placeholder !== "Write notes" || textarea.dirName !== "notes.dir") {
    throw new Error("expected textarea rows/cols/wrap/maxLength/minLength/placeholder/dirName props to set DOM properties");
  }
  if (textarea.getAttribute("rows") !== "4" || textarea.getAttribute("cols") !== "24" || textarea.getAttribute("wrap") !== "soft" || textarea.getAttribute("maxlength") !== "80" || textarea.getAttribute("minlength") !== "5" || textarea.getAttribute("placeholder") !== "Write notes" || textarea.getAttribute("dirname") !== "notes.dir") {
    throw new Error("expected textarea rows/cols/wrap/maxLength/minLength/placeholder/dirName props to remain reflected as attributes");
  }
  if (textarea.textContent !== "") {
    throw new Error(`expected textarea children not to write textContent, got '${textarea.textContent}'`);
  }

  const fileInput = findAll(root, (node) => node.tagName === "input" && node.getAttribute("type") === "file")[0];
  if (!fileInput || fileInput.multiple !== true) {
    throw new Error("expected file input multiple prop to set multiple property");
  }
  const emailInput = findAll(root, (node) => node.tagName === "input" && node.getAttribute("type") === "email")[0];
  if (!emailInput || emailInput.multiple !== true) {
    throw new Error("expected email input multiple prop to set multiple property");
  }
  const imageInput = findAll(root, (node) => node.tagName === "input" && node.getAttribute("type") === "image")[0];
  if (!imageInput) throw new Error(`missing image submit input in DOM: ${textSnapshot(root)}`);
  if (imageInput.src !== "submit.png" || imageInput.alt !== "Submit image" || imageInput.width !== "32" || imageInput.height !== "24") {
    throw new Error("expected image input src/alt/width/height props to set DOM properties");
  }
  if (imageInput.getAttribute("src") !== "submit.png" || imageInput.getAttribute("alt") !== "Submit image" || imageInput.getAttribute("width") !== "32" || imageInput.getAttribute("height") !== "24") {
    throw new Error("expected image input src/alt/width/height props to remain reflected as attributes");
  }

  const disabledButton = findButton(root, "Disabled action");
  if (disabledButton.disabled !== true) {
    throw new Error("expected disabled button property to be true");
  }
  if (disabledButton.value !== "disabled-action" || disabledButton.getAttribute("value") !== "disabled-action") {
    throw new Error("expected button value prop to set property and reflected attribute");
  }

  const video = findAll(root, (node) => node.tagName === "video")[0];
  if (!video) throw new Error(`missing video in DOM: ${textSnapshot(root)}`);
  if (video.controls !== true || video.muted !== true || video.loop !== true || video.autoplay !== true || video.playsInline !== true || video.disablePictureInPicture !== true || video.disableRemotePlayback !== true) {
    throw new Error("expected video boolean React props to set DOM properties");
  }
  if (video.poster !== "poster.png" || video.preload !== "metadata" || video.crossOrigin !== "anonymous" || video.controlsList !== "nodownload noplaybackrate" || video.width !== "160" || video.height !== "90") {
    throw new Error("expected video poster/preload/crossOrigin/controlsList/width/height props to set DOM properties");
  }
  if (video.getAttribute("poster") !== "poster.png" || video.getAttribute("preload") !== "metadata" || video.getAttribute("crossorigin") !== "anonymous" || video.getAttribute("controlslist") !== "nodownload noplaybackrate" || video.getAttribute("width") !== "160" || video.getAttribute("height") !== "90") {
    throw new Error("expected video poster/preload/crossOrigin/controlsList/width/height props to remain reflected as attributes");
  }
  const source = findAll(video, (node) => node.tagName === "source")[0];
  if (!source) throw new Error(`missing video source in DOM: ${textSnapshot(root)}`);
  if (source.src !== "demo.mp4" || source.type !== "video/mp4" || source.media !== "(min-width: 1px)" || source.width !== "320" || source.height !== "180") {
    throw new Error("expected source src/type/media/width/height props to set DOM properties");
  }
  if (source.getAttribute("src") !== "demo.mp4" || source.getAttribute("type") !== "video/mp4" || source.getAttribute("media") !== "(min-width: 1px)" || source.getAttribute("width") !== "320" || source.getAttribute("height") !== "180") {
    throw new Error("expected source src/type/media/width/height props to remain reflected as attributes");
  }
  const track = findAll(video, (node) => node.tagName === "track")[0];
  if (!track) throw new Error(`missing track in DOM: ${textSnapshot(root)}`);
  if (track.src !== "captions.vtt" || track.kind !== "captions" || track.srcLang !== "en" || track.label !== "English captions" || track.default !== true) {
    throw new Error("expected track src/kind/srcLang/label/default props to set DOM properties");
  }
  if (track.getAttribute("src") !== "captions.vtt" || track.getAttribute("kind") !== "captions" || track.getAttribute("srclang") !== "en" || track.getAttribute("label") !== "English captions") {
    throw new Error("expected track src/kind/srcLang/label props to remain reflected as attributes");
  }
  const mediaImage = findAll(root, (node) => node.tagName === "img")[0];
  if (!mediaImage) throw new Error(`missing image in DOM: ${textSnapshot(root)}`);
  if (mediaImage.loading !== "lazy" || mediaImage.decoding !== "async" || mediaImage.fetchPriority !== "high") {
    throw new Error("expected image loading/decoding/fetchPriority props to set DOM properties");
  }
  if (mediaImage.getAttribute("loading") !== "lazy" || mediaImage.getAttribute("decoding") !== "async" || mediaImage.getAttribute("fetchpriority") !== "high") {
    throw new Error("expected image loading/decoding/fetchPriority props to remain reflected as attributes");
  }

  const form = findAll(root, (node) => node.tagName === "form")[0];
  if (!form) throw new Error(`missing form in DOM: ${textSnapshot(root)}`);
  if (form.noValidate !== true) {
    throw new Error("expected form noValidate property to be true");
  }
  if (form.action !== "/submit" || form.acceptCharset !== "utf-8" || form.enctype !== "multipart/form-data" || form.method !== "post" || form.rel !== "noopener" || form.target !== "_self" || form.autocomplete !== "off") {
    throw new Error("expected form reflected string props to set DOM properties");
  }
  if (form.getAttribute("action") !== "/submit" || form.getAttribute("accept-charset") !== "utf-8" || form.getAttribute("enctype") !== "multipart/form-data" || form.getAttribute("method") !== "post" || form.getAttribute("rel") !== "noopener" || form.getAttribute("target") !== "_self" || form.getAttribute("autocomplete") !== "off") {
    throw new Error("expected form reflected string props to remain reflected as attributes");
  }

  const image = findAll(root, (node) => node.tagName === "img")[0];
  if (!image) throw new Error(`missing image in DOM: ${textSnapshot(root)}`);
  if (image.isMap !== true) {
    throw new Error("expected image isMap prop to set DOM property");
  }
  if (image.src !== "avatar.png" || image.alt !== "Avatar" || image.title !== "Profile avatar" || image.srcset !== "avatar.png 1x, avatar@2x.png 2x" || image.sizes !== "(min-width: 800px) 50vw, 100vw" || image.useMap !== "#avatar-map" || image.longDesc !== "/avatar-description" || image.crossOrigin !== "anonymous" || image.referrerPolicy !== "no-referrer") {
    throw new Error("expected image alt/title/srcSet/sizes/useMap/longDesc/crossOrigin/referrerPolicy props to set DOM properties");
  }
  if (image.getAttribute("src") !== "avatar.png" || image.getAttribute("alt") !== "Avatar" || image.getAttribute("title") !== "Profile avatar" || image.getAttribute("srcset") !== "avatar.png 1x, avatar@2x.png 2x" || image.getAttribute("sizes") !== "(min-width: 800px) 50vw, 100vw" || image.getAttribute("usemap") !== "#avatar-map" || image.getAttribute("longdesc") !== "/avatar-description" || image.getAttribute("crossorigin") !== "anonymous" || image.getAttribute("referrerpolicy") !== "no-referrer") {
    throw new Error("expected image alt/title/srcSet/sizes/useMap/longDesc/crossOrigin/referrerPolicy props to remain reflected as attributes");
  }

  const imageMapArea = findAll(root, (node) => node.tagName === "area")[0];
  if (!imageMapArea) throw new Error(`missing image map area in DOM: ${textSnapshot(root)}`);
  if (imageMapArea.alt !== "Avatar profile area" || imageMapArea.coords !== "0,0,32,32" || imageMapArea.shape !== "rect" || imageMapArea.href !== "/profile" || imageMapArea.hreflang !== "en" || imageMapArea.download !== "profile.txt" || imageMapArea.ping !== "/map-ping /map-audit" || imageMapArea.rel !== "nofollow" || imageMapArea.target !== "_self" || imageMapArea.referrerPolicy !== "no-referrer") {
    throw new Error("expected area alt/coords/shape/href/hrefLang/download/ping/rel/target/referrerPolicy props to set DOM properties");
  }
  if (imageMapArea.getAttribute("alt") !== "Avatar profile area" || imageMapArea.getAttribute("coords") !== "0,0,32,32" || imageMapArea.getAttribute("shape") !== "rect" || imageMapArea.getAttribute("href") !== "/profile" || imageMapArea.getAttribute("hreflang") !== "en" || imageMapArea.getAttribute("download") !== "profile.txt" || imageMapArea.getAttribute("ping") !== "/map-ping /map-audit" || imageMapArea.getAttribute("rel") !== "nofollow" || imageMapArea.getAttribute("target") !== "_self" || imageMapArea.getAttribute("referrerpolicy") !== "no-referrer") {
    throw new Error("expected area alt/coords/shape/href/hrefLang/download/ping/rel/target/referrerPolicy props to remain reflected as attributes");
  }

  const downloadLink = findAll(root, (node) => node.tagName === "a" && textOf(node) === "Download report")[0];
  if (!downloadLink) throw new Error(`missing download link in DOM: ${textSnapshot(root)}`);
  if (downloadLink.href !== "/download/report.txt" || downloadLink.charset !== "utf-8" || downloadLink.coords !== "0,0,16,16" || downloadLink.shape !== "rect" || downloadLink.hreflang !== "en" || downloadLink.download !== "report.txt" || downloadLink.ping !== "/audit/report /audit/download" || downloadLink.rel !== "noopener" || downloadLink.type !== "text/plain" || downloadLink.target !== "_blank" || downloadLink.referrerPolicy !== "origin") {
    throw new Error("expected anchor href/charSet/coords/shape/hrefLang/download/ping/rel/type/target/referrerPolicy props to set DOM properties");
  }
  if (downloadLink.getAttribute("href") !== "/download/report.txt" || downloadLink.getAttribute("charset") !== "utf-8" || downloadLink.getAttribute("coords") !== "0,0,16,16" || downloadLink.getAttribute("shape") !== "rect" || downloadLink.getAttribute("hreflang") !== "en" || downloadLink.getAttribute("download") !== "report.txt" || downloadLink.getAttribute("ping") !== "/audit/report /audit/download" || downloadLink.getAttribute("rel") !== "noopener" || downloadLink.getAttribute("type") !== "text/plain" || downloadLink.getAttribute("target") !== "_blank" || downloadLink.getAttribute("referrerpolicy") !== "origin") {
    throw new Error("expected anchor href/charSet/coords/shape/hrefLang/download/ping/rel/type/target/referrerPolicy props to remain reflected as attributes");
  }

  const stylesheetLink = findAll(root, (node) => node.tagName === "link")[0];
  if (!stylesheetLink) throw new Error(`missing link element in DOM: ${textSnapshot(root)}`);
  if (stylesheetLink.rel !== "preload" || stylesheetLink.href !== "hero.avif" || stylesheetLink.hreflang !== "en-US" || stylesheetLink.charset !== "utf-8" || stylesheetLink.as !== "image" || stylesheetLink.blocking !== "render" || stylesheetLink.media !== "screen" || stylesheetLink.type !== "image/avif" || stylesheetLink.imageSrcset !== "hero.avif 1x, hero@2x.avif 2x" || stylesheetLink.imageSizes !== "100vw" || stylesheetLink.integrity !== "sha256-demo" || stylesheetLink.fetchPriority !== "high" || stylesheetLink.crossOrigin !== "anonymous" || stylesheetLink.referrerPolicy !== "no-referrer" || stylesheetLink.disabled !== true) {
    throw new Error("expected link rel/href/hrefLang/charSet/as/blocking/media/type/imageSrcSet/imageSizes/integrity/fetchPriority/crossOrigin/referrerPolicy/disabled props to set DOM properties");
  }
  if (stylesheetLink.getAttribute("rel") !== "preload" || stylesheetLink.getAttribute("href") !== "hero.avif" || stylesheetLink.getAttribute("hreflang") !== "en-US" || stylesheetLink.getAttribute("charset") !== "utf-8" || stylesheetLink.getAttribute("as") !== "image" || stylesheetLink.getAttribute("blocking") !== "render" || stylesheetLink.getAttribute("media") !== "screen" || stylesheetLink.getAttribute("type") !== "image/avif" || stylesheetLink.getAttribute("imagesrcset") !== "hero.avif 1x, hero@2x.avif 2x" || stylesheetLink.getAttribute("imagesizes") !== "100vw" || stylesheetLink.getAttribute("integrity") !== "sha256-demo" || stylesheetLink.getAttribute("fetchpriority") !== "high" || stylesheetLink.getAttribute("crossorigin") !== "anonymous" || stylesheetLink.getAttribute("referrerpolicy") !== "no-referrer") {
    throw new Error("expected link rel/href/hrefLang/charSet/as/blocking/media/type/imageSrcSet/imageSizes/integrity/fetchPriority/crossOrigin/referrerPolicy props to remain reflected as attributes");
  }

  const iconLink = findAll(root, (node) => node.tagName === "link" && node.rel === "icon")[0];
  if (!iconLink) throw new Error(`missing icon link element in DOM: ${textSnapshot(root)}`);
  if (iconLink.href !== "/favicon.svg" || iconLink.sizes !== "any" || iconLink.type !== "image/svg+xml" || iconLink.target !== "_self") {
    throw new Error("expected icon link href/sizes/type/target props to set DOM properties");
  }
  if (iconLink.getAttribute("href") !== "/favicon.svg" || iconLink.getAttribute("sizes") !== "any" || iconLink.getAttribute("type") !== "image/svg+xml" || iconLink.getAttribute("target") !== "_self") {
    throw new Error("expected icon link href/sizes/type/target props to remain reflected as attributes");
  }

  const baseElement = findAll(root, (node) => node.tagName === "base")[0];
  if (!baseElement) throw new Error(`missing base element in DOM: ${textSnapshot(root)}`);
  if (baseElement.href !== "/docs/" || baseElement.target !== "_self") {
    throw new Error("expected base href/target props to set DOM properties");
  }
  if (baseElement.getAttribute("href") !== "/docs/" || baseElement.getAttribute("target") !== "_self") {
    throw new Error("expected base href/target props to remain reflected as attributes");
  }

  const themeMeta = findAll(root, (node) => node.tagName === "meta" && node.content === "#336699")[0];
  if (!themeMeta) throw new Error(`missing meta httpEquiv/content element in DOM: ${textSnapshot(root)}`);
  if (themeMeta.httpEquiv !== "theme-color" || themeMeta.content !== "#336699") {
    throw new Error("expected meta httpEquiv/content props to set DOM properties");
  }
  if (themeMeta.getAttribute("http-equiv") !== "theme-color" || themeMeta.getAttribute("content") !== "#336699") {
    throw new Error("expected meta httpEquiv/content props to remain reflected as attributes");
  }

  const styleElement = findAll(root, (node) => node.tagName === "style")[0];
  if (!styleElement) throw new Error(`missing style element in DOM: ${textSnapshot(root)}`);
  if (styleElement.media !== "screen" || styleElement.type !== "text/css") {
    throw new Error("expected style media/type props to set DOM properties");
  }
  if (styleElement.getAttribute("media") !== "screen" || styleElement.getAttribute("type") !== "text/css") {
    throw new Error("expected style media/type props to remain reflected as attributes");
  }

  const submitButton = findButton(root, "Skip validation");
  if (submitButton.type !== "submit" || submitButton.getAttribute("type") !== "submit") {
    throw new Error("expected button type prop to set property and reflected attribute");
  }
  if (submitButton.formNoValidate !== true) {
    throw new Error("expected button formNoValidate property to be true");
  }
  if (submitButton.formAction !== "/skip" || submitButton.formEnctype !== "text/plain" || submitButton.formMethod !== "post" || submitButton.formTarget !== "_blank") {
    throw new Error("expected button formAction/formEncType/formMethod/formTarget props to set DOM properties");
  }
  if (submitButton.getAttribute("formaction") !== "/skip" || submitButton.getAttribute("formenctype") !== "text/plain" || submitButton.getAttribute("formmethod") !== "post" || submitButton.getAttribute("formtarget") !== "_blank") {
    throw new Error("expected button formAction/formEncType/formMethod/formTarget props to remain reflected as attributes");
  }

  findButton(root, "Nested event").dispatchEvent({ type: "click" });
  expectText(root, "Captured: 1");
  expectText(root, "Bubbled: 1");

  const mouseBoundary = findAll(root, (node) => textOf(node) === "Mouse boundary")[0];
  if (!mouseBoundary) throw new Error(`missing mouse boundary in DOM: ${textSnapshot(root)}`);
  mouseBoundary.dispatchEvent({ type: "mouseenter" });
  expectText(root, "Mouse enters: 1");
  mouseBoundary.dispatchEvent({ type: "mouseleave" });
  expectText(root, "Mouse leave captures: 1");

  const relatedZone = findAll(root, (node) => textOf(node) === "Related target zone")[0];
  if (!relatedZone) throw new Error(`missing related target zone in DOM: ${textSnapshot(root)}`);
  range.setAttribute("id", "range-source");
  range.setAttribute("name", "rangeSource");
  relatedZone.dispatchEvent({ type: "mouseover", relatedTarget: range });
  const relatedMatch = textSnapshot(root).match(/Related target: (\d+)/);
  if (!relatedMatch || Number(relatedMatch[1]) <= 0) {
    throw new Error(`expected related target handle to be recorded, got '${textSnapshot(root)}'`);
  }
  expectText(root, "Related target name: rangeSource");
  expectText(root, "Related target id: range-source");

  const scrollable = findAll(root, (node) => textOf(node) === "Scrollable panel")[0];
  if (!scrollable) throw new Error(`missing scrollable panel in DOM: ${textSnapshot(root)}`);
  scrollable.dispatchEvent({ type: "scroll" });
  expectText(root, "Scrolls: 1");

  const togglePanel = findAll(root, (node) => node.tagName === "details" && textOf(node).includes("Toggle panel"))[0];
  if (!togglePanel) throw new Error(`missing toggle details in DOM: ${textSnapshot(root)}`);
  togglePanel.dispatchEvent({ type: "toggle" });
  expectText(root, "Toggles: 1");

  findButton(root, "Double event").dispatchEvent({ type: "dblclick" });
  expectText(root, "Double clicks: 1");

  const wheelArea = findAll(root, (node) => textOf(node) === "Wheel area")[0];
  if (!wheelArea) throw new Error(`missing wheel area in DOM: ${textSnapshot(root)}`);
  wheelArea.dispatchEvent({ type: "wheel", deltaX: 3, deltaY: -7, deltaZ: 1, deltaMode: 1 });
  expectText(root, "Wheel delta: 3,-7,1");
  expectText(root, "Wheel mode: 1");

  const touchArea = findAll(root, (node) => textOf(node) === "Touch area")[0];
  if (!touchArea) throw new Error(`missing touch area in DOM: ${textSnapshot(root)}`);
  touchArea.dispatchEvent({ type: "touchstart", touches: [{ identifier: 9, clientX: 31, clientY: 47 }, { identifier: 10, clientX: 50, clientY: 60 }] });
  expectText(root, "Touches: 2");
  expectText(root, "Touch id: 9");
  expectText(root, "Touch client: 31,47");

  const dropArea = findAll(root, (node) => textOf(node) === "Drop area")[0];
  if (!dropArea) throw new Error(`missing drop area in DOM: ${textSnapshot(root)}`);
  dropArea.dispatchEvent({ type: "drop", dataTransfer: { getData: (kind) => kind === "text" ? "drop text" : "" } });
  expectText(root, "Drop text: drop text");

  const editableRegion = findAll(root, (node) => textOf(node) === "Editable region")[0];
  if (!editableRegion) throw new Error(`missing editable region in DOM: ${textSnapshot(root)}`);
  if (editableRegion.contentEditable !== "true") {
    throw new Error(`expected contentEditable property=true, got '${editableRegion.contentEditable}'`);
  }
  if (editableRegion.getAttribute("suppressContentEditableWarning") !== null || editableRegion.getAttribute("suppressHydrationWarning") !== null) {
    throw new Error("expected React suppress* warning props not to be emitted as DOM attributes");
  }
  if (editableRegion.spellcheck !== false) {
    throw new Error(`expected spellcheck property=false, got '${editableRegion.spellcheck}'`);
  }
  if (editableRegion.getAttribute("contenteditable") !== "true") {
    throw new Error(`expected normalized contenteditable=true, got '${editableRegion.getAttribute("contenteditable")}'`);
  }
  if (editableRegion.getAttribute("spellcheck") !== "false") {
    throw new Error(`expected normalized spellcheck=false, got '${editableRegion.getAttribute("spellcheck")}'`);
  }
  if (editableRegion.inputMode !== "text" || editableRegion.enterKeyHint !== "send" || editableRegion.autoCapitalize !== "sentences" || editableRegion.autocorrect !== "on") {
    throw new Error("expected editable region editing hint props to set DOM properties");
  }
  if (editableRegion.getAttribute("inputmode") !== "text" || editableRegion.getAttribute("enterkeyhint") !== "send" || editableRegion.getAttribute("autocapitalize") !== "sentences" || editableRegion.getAttribute("autocorrect") !== "on") {
    throw new Error("expected editable region editing hint props to remain reflected as attributes");
  }
  if (editableRegion.translate !== false) {
    throw new Error(`expected translate property=false, got '${editableRegion.translate}'`);
  }
  if (editableRegion.getAttribute("translate") !== "no") {
    throw new Error(`expected translate=no, got '${editableRegion.getAttribute("translate")}'`);
  }

  const globalPropsPanel = findAll(root, (node) => textOf(node) === "Global props panel")[0];
  if (!globalPropsPanel) throw new Error(`missing global props panel in DOM: ${textSnapshot(root)}`);
  if (globalPropsPanel.id !== "global-props-panel" || globalPropsPanel.name !== "global-panel" || globalPropsPanel.nonce !== "nonce-panel" || globalPropsPanel.lang !== "en-US" || globalPropsPanel.dir !== "rtl" || globalPropsPanel.role !== "note" || globalPropsPanel.accessKey !== "g" || globalPropsPanel.tabIndex !== "2" || globalPropsPanel.slot !== "toolbar" || globalPropsPanel.part !== "panel" || globalPropsPanel.popover !== "auto") {
    throw new Error("expected global string props to set DOM properties");
  }
  if (globalPropsPanel.getAttribute("id") !== "global-props-panel" || globalPropsPanel.getAttribute("name") !== "global-panel" || globalPropsPanel.getAttribute("nonce") !== "nonce-panel" || globalPropsPanel.getAttribute("lang") !== "en-US" || globalPropsPanel.getAttribute("dir") !== "rtl" || globalPropsPanel.getAttribute("role") !== "note" || globalPropsPanel.getAttribute("accesskey") !== "g" || globalPropsPanel.getAttribute("tabindex") !== "2" || globalPropsPanel.getAttribute("slot") !== "toolbar" || globalPropsPanel.getAttribute("part") !== "panel" || globalPropsPanel.getAttribute("popover") !== "auto") {
    throw new Error("expected global string props to remain reflected as attributes");
  }

  const microdataItem = findAll(root, (node) => textOf(node) === "Microdata item")[0];
  if (!microdataItem) throw new Error(`missing microdata item in DOM: ${textSnapshot(root)}`);
  if (microdataItem.itemScope !== true || microdataItem.itemType !== "https://schema.org/Thing" || microdataItem.itemID !== "thing-1" || microdataItem.itemRef !== "global-props-panel" || microdataItem.itemProp !== "about") {
    throw new Error("expected microdata props to set DOM properties");
  }
  if (microdataItem.getAttribute("itemtype") !== "https://schema.org/Thing" || microdataItem.getAttribute("itemid") !== "thing-1" || microdataItem.getAttribute("itemref") !== "global-props-panel" || microdataItem.getAttribute("itemprop") !== "about") {
    throw new Error("expected microdata string props to remain reflected as attributes");
  }

  const hiddenPanel = findAll(root, (node) => textOf(node) === "Hidden inert panel")[0];
  if (!hiddenPanel) throw new Error(`missing hidden inert panel in DOM: ${textSnapshot(root)}`);
  if (hiddenPanel.hidden !== true || hiddenPanel.inert !== true || hiddenPanel.draggable !== true) {
    throw new Error("expected hidden, inert, and draggable DOM properties to be true");
  }

  const readonlyInput = findAll(root, (node) => node.tagName === "input" && node.value === "fixed")[0];
  if (!readonlyInput) throw new Error(`missing readOnly input in DOM: ${textSnapshot(root)}`);
  if (readonlyInput.readOnly !== true) {
    throw new Error("expected readOnly input property to be true");
  }
  if (readonlyInput.required !== true) {
    throw new Error("expected required input property to be true");
  }

  const defaultInput = findAll(root, (node) => node.tagName === "input" && node.value === "seed")[0];
  if (!defaultInput) throw new Error(`missing defaultValue input in DOM: ${textSnapshot(root)}`);
  defaultInput.value = "user typed";

  const defaultCheckbox = findAll(root, (node) => node.tagName === "input" && node.getAttribute("type") === "checkbox")[0];
  if (!defaultCheckbox) throw new Error(`missing defaultChecked checkbox in DOM: ${textSnapshot(root)}`);
  if (defaultCheckbox.checked !== true) {
    throw new Error("expected defaultChecked checkbox to initialize checked property");
  }
  defaultCheckbox.checked = false;

  const svg = findAll(root, (node) => node.tagName === "svg")[0];
  const rect = findAll(root, (node) => node.tagName === "rect")[0];
  const td = findAll(root, (node) => node.tagName === "td")[0];
  const time = findAll(root, (node) => node.tagName === "time")[0];
  const meta = findAll(root, (node) => node.tagName === "meta" && node.charset === "utf-8")[0];
  if (!td) throw new Error(`missing table cell in DOM: ${textSnapshot(root)}`);
  if (td.rowSpan !== "2") throw new Error(`expected rowSpan property=2, got '${td.rowSpan}'`);
  if (td.colSpan !== "3") throw new Error(`expected colSpan property=3, got '${td.colSpan}'`);
  if (td.headers !== "h-name") throw new Error(`expected td headers property=h-name, got '${td.headers}'`);
  if (td.width !== "240") throw new Error(`expected td width property=240, got '${td.width}'`);
  if (td.height !== "48") throw new Error(`expected td height property=48, got '${td.height}'`);
  if (td.getAttribute("rowspan") !== "2") throw new Error(`expected normalized rowspan=2, got '${td.getAttribute("rowspan")}'`);
  if (td.getAttribute("colspan") !== "3") throw new Error(`expected normalized colspan=3, got '${td.getAttribute("colspan")}'`);
  if (td.getAttribute("headers") !== "h-name") throw new Error(`expected td headers=h-name, got '${td.getAttribute("headers")}'`);
  if (td.getAttribute("width") !== "240") throw new Error(`expected td width=240, got '${td.getAttribute("width")}'`);
  if (td.getAttribute("height") !== "48") throw new Error(`expected td height=48, got '${td.getAttribute("height")}'`);
  const th = findAll(root, (node) => node.tagName === "th")[0];
  const colgroup = findAll(root, (node) => node.tagName === "colgroup")[0];
  const col = findAll(root, (node) => node.tagName === "col")[0];
  if (!th) throw new Error(`missing table header cell in DOM: ${textSnapshot(root)}`);
  if (!colgroup || !col) throw new Error(`missing colgroup/col in DOM: ${textSnapshot(root)}`);
  if (colgroup.span !== "2" || colgroup.width !== "120" || col.span !== "1" || col.width !== "80") {
    throw new Error("expected colgroup/col span/width props to set DOM properties");
  }
  if (colgroup.getAttribute("span") !== "2" || colgroup.getAttribute("width") !== "120" || col.getAttribute("span") !== "1" || col.getAttribute("width") !== "80") {
    throw new Error("expected colgroup/col span/width props to remain reflected as attributes");
  }
  if (th.scope !== "col" || th.abbr !== "Nm" || th.headers !== "h-group" || th.width !== "120" || th.height !== "32") {
    throw new Error("expected th scope/abbr/headers/width/height props to set DOM properties");
  }
  if (th.getAttribute("scope") !== "col" || th.getAttribute("abbr") !== "Nm" || th.getAttribute("headers") !== "h-group" || th.getAttribute("width") !== "120" || th.getAttribute("height") !== "32") {
    throw new Error("expected th scope/abbr/headers/width/height props to remain reflected as attributes");
  }
  const orderedList = findAll(root, (node) => node.tagName === "ol")[0];
  if (!orderedList) throw new Error(`missing ordered list in DOM: ${textSnapshot(root)}`);
  if (orderedList.start !== "3" || orderedList.type !== "A" || orderedList.getAttribute("start") !== "3" || orderedList.getAttribute("type") !== "A") {
    throw new Error("expected ol start/type props to set properties and reflected attributes");
  }
  if (orderedList.reversed !== true) {
    throw new Error("expected ol reversed prop to set property");
  }
  const orderedListItem = findAll(orderedList, (node) => node.tagName === "li")[0];
  if (!orderedListItem) throw new Error(`missing ordered list item in DOM: ${textSnapshot(root)}`);
  if (orderedListItem.value !== "5" || orderedListItem.getAttribute("value") !== "5") {
    throw new Error("expected li value prop to set property and reflected attribute");
  }
  const dataElement = findAll(root, (node) => node.tagName === "data")[0];
  if (!dataElement) throw new Error(`missing data element in DOM: ${textSnapshot(root)}`);
  if (dataElement.value !== "product-42" || dataElement.getAttribute("value") !== "product-42") {
    throw new Error("expected data value prop to set property and reflected attribute");
  }
  const paramElement = findAll(root, (node) => node.tagName === "param")[0];
  if (!paramElement) throw new Error(`missing param element in DOM: ${textSnapshot(root)}`);
  if (paramElement.name !== "quality" || paramElement.value !== "high") {
    throw new Error("expected param name/value props to set DOM properties");
  }
  if (paramElement.getAttribute("name") !== "quality" || paramElement.getAttribute("value") !== "high") {
    throw new Error("expected param name/value props to remain reflected as attributes");
  }
  const quotedBlock = findAll(root, (node) => node.tagName === "blockquote")[0];
  const inlineQuote = findAll(root, (node) => node.tagName === "q")[0];
  const deletedText = findAll(root, (node) => node.tagName === "del")[0];
  const insertedText = findAll(root, (node) => node.tagName === "ins")[0];
  if (!quotedBlock || !inlineQuote || !deletedText || !insertedText) {
    throw new Error(`missing cite-bearing text semantics in DOM: ${textSnapshot(root)}`);
  }
  if (quotedBlock.cite !== "/quotes/source" || inlineQuote.cite !== "/quotes/inline" || deletedText.cite !== "/edits/old" || insertedText.cite !== "/edits/new") {
    throw new Error("expected blockquote/q/del/ins cite props to set DOM properties");
  }
  if (deletedText.dateTime !== "2026-01-01" || insertedText.dateTime !== "2026-01-02") {
    throw new Error("expected del/ins dateTime props to set DOM properties");
  }
  if (quotedBlock.getAttribute("cite") !== "/quotes/source" || inlineQuote.getAttribute("cite") !== "/quotes/inline" || deletedText.getAttribute("cite") !== "/edits/old" || insertedText.getAttribute("cite") !== "/edits/new") {
    throw new Error("expected blockquote/q/del/ins cite props to remain reflected as attributes");
  }
  if (deletedText.getAttribute("datetime") !== "2026-01-01" || insertedText.getAttribute("datetime") !== "2026-01-02") {
    throw new Error("expected del/ins dateTime props to remain reflected as attributes");
  }
  if (time?.dateTime !== "2026-06-08") {
    throw new Error(`expected time dateTime property=2026-06-08, got '${time?.dateTime}'`);
  }
  if (!time || time.getAttribute("datetime") !== "2026-06-08") {
    throw new Error(`expected normalized datetime on time element, got '${time?.getAttribute("datetime")}'`);
  }
  if (meta?.charset !== "utf-8") {
    throw new Error(`expected meta charset property=utf-8, got '${meta?.charset}'`);
  }
  if (!meta || meta.getAttribute("charset") !== "utf-8") {
    throw new Error(`expected normalized charset on meta element, got '${meta?.getAttribute("charset")}'`);
  }
  if (!svg || !rect) throw new Error(`missing SVG surface in DOM: ${textSnapshot(root)}`);
  if (svg.getAttribute("viewBox") !== "0 0 10 10") throw new Error(`expected SVG viewBox, got '${svg.getAttribute("viewBox")}'`);
  if (rect.getAttribute("fill") !== "currentColor") throw new Error(`expected rect fill currentColor, got '${rect.getAttribute("fill")}'`);
  if (rect.getAttribute("stroke-width") !== "2") throw new Error(`expected normalized stroke-width=2, got '${rect.getAttribute("stroke-width")}'`);
  if (rect.getAttribute("stroke-linecap") !== "round") throw new Error(`expected normalized stroke-linecap=round, got '${rect.getAttribute("stroke-linecap")}'`);
  if (rect.getAttribute("stroke-linejoin") !== "round") throw new Error(`expected normalized stroke-linejoin=round, got '${rect.getAttribute("stroke-linejoin")}'`);
  if (rect.getAttribute("fill-rule") !== "evenodd") throw new Error(`expected normalized fill-rule=evenodd, got '${rect.getAttribute("fill-rule")}'`);
  if (rect.getAttribute("clip-rule") !== "evenodd") throw new Error(`expected normalized clip-rule=evenodd, got '${rect.getAttribute("clip-rule")}'`);
  if (rect.getAttribute("vector-effect") !== "non-scaling-stroke") throw new Error(`expected normalized vector-effect=non-scaling-stroke, got '${rect.getAttribute("vector-effect")}'`);
  if (rect.getAttribute("xlink:href") !== "#shape") throw new Error(`expected normalized xlink:href=#shape, got '${rect.getAttribute("xlink:href")}'`);

  range.dispatchEvent({ type: "pointerdown", pointerId: 42, pointerType: "pen", isPrimary: true });
  expectText(root, "Range value: 55");
  expectText(root, "Pointer id: 42");
  expectText(root, "Pointer type: pen");
  expectText(root, "Pointer primary: 1");
  if (defaultInput.value !== "user typed") {
    throw new Error(`expected defaultValue input not to be reset after render, got '${defaultInput.value}'`);
  }
  if (defaultCheckbox.checked !== false) {
    throw new Error("expected defaultChecked checkbox not to be reset after render");
  }
  if (options[1].selected !== false) {
    throw new Error("expected defaultSelected option not to be reset after render");
  }
  if (defaultSingleSelect.value !== "primary") {
    throw new Error(`expected defaultValue single select not to be reset after render, got '${defaultSingleSelect.value}'`);
  }
  if (defaultMultiSelect.value !== "zeta") {
    throw new Error(`expected defaultValue multiple select not to be reset after render, got '${defaultMultiSelect.value}'`);
  }
}

async function verifyControlledInput(outDir) {
  const { root } = await boot(outDir);
  expectText(root, "Controlled input");
  expectText(root, "Echo:");
  expectText(root, "Current value:");
  expectText(root, "Enabled: 0");
  expectText(root, "Current checked: 0");
  expectText(root, "Submits: 0");
  expectText(root, "Event:");
  expectText(root, "Input target: 0");
  expectText(root, "Input target name:");
  expectText(root, "Input target id:");
  expectText(root, "Submit target: 0");
  expectText(root, "Submit target name:");
  expectText(root, "Submit target id:");
  expectText(root, "Default prevented: 0");
  expectText(root, "Time stamp: 0");
  expectText(root, "Button: 0");
  expectText(root, "Client: 0,0");
  expectText(root, "Page: 0,0");
  expectText(root, "Screen: 0,0");
  expectText(root, "Modifiers: 0");

  const input = findInput(root);
  input.value = "reactive sax";
  input.dispatchEvent({ type: "input" });

  expectText(root, "Echo: reactive sax");
  expectText(root, "Current value: reactive sax");
  if (input.value !== "reactive sax") {
    throw new Error(`expected controlled input value to stay synced, got '${input.value}'`);
  }
  const inputTargetMatch = textSnapshot(root).match(/Input target: (\d+)/);
  if (!inputTargetMatch || Number(inputTargetMatch[1]) <= 0) {
    throw new Error(`expected event target handle to be recorded, got '${textSnapshot(root)}'`);
  }
  expectText(root, "Input target name: message");
  expectText(root, "Input target id: message-input");

  const checkbox = findInput(root, 1);
  if (checkbox.checked !== false) {
    throw new Error(`expected checkbox to start unchecked, got '${checkbox.checked}'`);
  }

  checkbox.checked = true;
  checkbox.dispatchEvent({ type: "change" });
  expectText(root, "Enabled: 1");
  expectText(root, "Current checked: 1");
  if (checkbox.checked !== true) {
    throw new Error(`expected controlled checkbox to stay checked, got '${checkbox.checked}'`);
  }

  checkbox.checked = false;
  checkbox.dispatchEvent({ type: "change" });
  expectText(root, "Enabled: 0");
  expectText(root, "Current checked: 0");
  if (checkbox.checked !== false) {
    throw new Error(`expected controlled checkbox to stay unchecked, got '${checkbox.checked}'`);
  }

  const form = findAll(root, (node) => node.tagName === "form")[0];
  if (!form) throw new Error(`missing form in DOM: ${textSnapshot(root)}`);
  let secondarySubmitCalled = false;
  form.addEventListener("submit", () => {
    secondarySubmitCalled = true;
  });
  const submitEvent = { type: "submit", timeStamp: 1234.75, button: 2, clientX: 17, clientY: 29, pageX: 117, pageY: 129, screenX: 217, screenY: 229, shiftKey: true, ctrlKey: true, altKey: false, metaKey: true };
  const dispatchResult = form.dispatchEvent(submitEvent);
  expectText(root, "Submits: 1");
  expectText(root, "Event: submit");
  expectText(root, "Default prevented: 1");
  expectText(root, "Time stamp: 1234");
  expectText(root, "Button: 2");
  expectText(root, "Client: 17,29");
  expectText(root, "Page: 117,129");
  expectText(root, "Screen: 217,229");
  expectText(root, "Modifiers: 11");
  if (dispatchResult !== false || submitEvent.defaultPrevented !== true) {
    throw new Error("expected submit handler to prevent default");
  }
  if (submitEvent.cancelBubble !== true || secondarySubmitCalled) {
    throw new Error("expected submit handler to stop propagation/listener continuation");
  }
  const submitTargetMatch = textSnapshot(root).match(/Submit target: (\d+)/);
  if (!submitTargetMatch || Number(submitTargetMatch[1]) <= 0) {
    throw new Error(`expected currentTarget handle to be recorded, got '${textSnapshot(root)}'`);
  }
  expectText(root, "Submit target name: controlled");
  expectText(root, "Submit target id: controlled-form");
}

async function verifyCounter(outDir) {
  const { root } = await boot(outDir);
  expectTagText(root, "h1", 0, "0");
  expectText(root, "Last updated: 0 ms ago");

  findButton(root, "+1").dispatchEvent({ type: "click" });
  expectTagText(root, "h1", 0, "1");

  findButton(root, "-1").dispatchEvent({ type: "click" });
  expectTagText(root, "h1", 0, "0");

  findButton(root, "-1").dispatchEvent({ type: "click" });
  expectTagText(root, "h1", 0, "-1");

  findButton(root, "Reset").dispatchEvent({ type: "click" });
  expectTagText(root, "h1", 0, "0");
}

async function verifyTodo(outDir) {
  const { root } = await boot(outDir);
  expectText(root, "TodoList");
  expectText(root, "Items: 0");

  const input = findInput(root);
  input.value = "write sax demo";
  findButton(root, "Add").dispatchEvent({ type: "click" });
  expectText(root, "Items: 1");
  expectTagText(root, "li", 0, "write sax demo");
  if (input.value !== "") throw new Error(`expected input to clear after add, got '${input.value}'`);

  input.value = "ship wasm";
  findButton(root, "Add").dispatchEvent({ type: "click" });
  expectText(root, "Items: 2");
  expectTagText(root, "li", 1, "ship wasm");

  findButton(root, "Delete last").dispatchEvent({ type: "click" });
  expectText(root, "Items: 1");
  expectTagText(root, "li", 0, "write sax demo");
  expectTagText(root, "li", 1, "");
}

async function verifySecurity(outDir) {
  const { document, airlockModule } = await boot(outDir);
  const { sax_airlock, sax_debug_get_memory } = airlockModule;
  const mem = sax_debug_get_memory();
  if (!mem) throw new Error("missing airlock memory after boot");

  const writeBytes = (text) => {
    const bytes = new TextEncoder().encode(text);
    const ptr = sax_airlock.malloc(bytes.length || 1);
    new Uint8Array(mem.buffer, Number(ptr), bytes.length).set(bytes);
    return { ptr, len: bytes.length };
  };

  const expectThrow = async (name, fn, expected) => {
    try {
      await fn();
      throw new Error(`${name} should have thrown`);
    } catch (err) {
      const text = err instanceof Error ? err.message : String(err);
      if (!text.includes(expected)) {
        throw new Error(`${name} expected '${expected}', got '${text}'`);
      }
    }
  };

  const badTag = writeBytes("script");
  await expectThrow("script tag", () => sax_airlock.sax_dom_create(badTag.ptr, badTag.len), "SaxUnknownTag");

  const divTag = writeBytes("div");
  const divHandle = sax_airlock.sax_dom_create(divTag.ptr, divTag.len);
  const badAttr = writeBytes("innerHTML");
  const badValue = writeBytes("<img src=x onerror=alert(1)>");
  await expectThrow(
    "innerHTML attr",
    () => sax_airlock.sax_dom_set_attr(divHandle, badAttr.ptr, badAttr.len, badValue.ptr, badValue.len),
    "SaxInvalidAttribute",
  );

  const buttonTag = writeBytes("button");
  const buttonHandle = sax_airlock.sax_dom_create(buttonTag.ptr, buttonTag.len);
  const evalAttr = writeBytes("onclick");
  const evalValue = writeBytes("eval(alert(1))");
  await expectThrow(
    "inline onclick attr",
    () => sax_airlock.sax_dom_set_attr(buttonHandle, evalAttr.ptr, evalAttr.len, evalValue.ptr, evalValue.len),
    "SaxInvalidAttribute",
  );

  const anchorTag = writeBytes("a");
  const anchorHandle = sax_airlock.sax_dom_create(anchorTag.ptr, anchorTag.len);
  const pingProp = writeBytes("ping");
  const badPingValue = writeBytes("/audit javascript:alert(1)");
  await expectThrow(
    "javascript ping token",
    () => sax_airlock.sax_dom_set_str_prop(anchorHandle, pingProp.ptr, pingProp.len, badPingValue.ptr, badPingValue.len),
    "SaxInvalidAttribute",
  );

  if (document.app.children.length === 0) {
    throw new Error("security boot should preserve mounted SAX app");
  }
}

const [, , outDir, scenario] = process.argv;
if (!outDir || !scenario) {
  console.error("usage: node tools/verify_sax_runtime.mjs <sax-output-dir> <counter|dashboard|security|todo|typed>");
  process.exit(2);
}

try {
  if (scenario === "counter") {
    await verifyCounter(outDir);
  } else if (scenario === "dashboard") {
    await verifyDashboard(outDir);
  } else if (scenario === "security") {
    await verifySecurity(outDir);
  } else if (scenario === "todo") {
    await verifyTodo(outDir);
  } else if (scenario === "typed") {
    await verifyTyped(outDir);
  } else if (scenario === "composition") {
    await verifyComposition(outDir);
  } else if (scenario === "component-events") {
    await verifyComponentEvents(outDir);
  } else if (scenario === "dom-surface") {
    await verifyDomSurface(outDir);
  } else if (scenario === "controlled-input") {
    await verifyControlledInput(outDir);
  } else {
    throw new Error(`unknown SAX runtime scenario '${scenario}'`);
  }
  console.log(`[PASS] sax runtime ${scenario}`);
} catch (err) {
  console.error(err instanceof Error ? err.stack : err);
  process.exit(1);
}
