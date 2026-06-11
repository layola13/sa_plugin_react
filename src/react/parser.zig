const std = @import("std");

pub const ParseError = error{
    OutOfMemory,
    UnexpectedToken,
    UnexpectedEOF,
    InvalidComponentName,
    InvalidStateVar,
    InvalidDOMTag,
    InvalidEventName,
    InvalidHandler,
    DuplicateStateVar,
    DuplicateHandler,
    DuplicateRoute,
    InvalidInterpolation,
    UnknownTag,
    UnknownEvent,
    InvalidAttribute,
    InvalidRelease,
    InvalidComponentBody,
    InvalidRouter,
    InvalidPage,
    InvalidStateInit,
    InvalidStateType,
    InvalidNativeEscape,
};

pub const StateType = enum {
    i1,
    i32,
    i64,
    f64,
    ptr,
};

pub const StateVar = struct {
    name: []const u8,
    init_expr: []const u8,
    ty: StateType,
    alloc_size: ?usize = null,
};

pub const TextPiece = union(enum) {
    text: []const u8,
    interpolation: Expr,
    json_string_interpolation: Expr,
    json_object_spread: JsonObjectSpreadPiece,
};

pub const JsonObjectSpreadPiece = struct {
    expr: Expr,
    prefix_comma: bool,
};

pub const AttrValue = union(enum) {
    literal: []const u8,
    interpolation: Expr,
    template: []TextPiece,
};

pub const Expr = struct {
    expr: []const u8,
    deps: []const []const u8,
};

pub const Attribute = struct {
    name: []const u8,
    value: AttrValue,
    is_event: bool = false,
    event_handler: ?[]const u8 = null,
    is_object_prop: bool = false,
};

pub const DomChild = union(enum) {
    text: TextPiece,
    node_index: usize,
};

pub const DomNode = struct {
    tag: []const u8,
    attrs: []Attribute,
    children: []DomChild,
    self_closing: bool,
    alias: []const u8,
    key: ?Expr = null,
    is_user_component: bool = false,
    text_index: ?usize = null,
};

pub const Handler = struct {
    name: []const u8,
    body: []const u8,
    is_ffi_wrapper: bool = false,
};

pub const RoutePage = struct {
    path: []const u8,
    component: []const u8,
};

pub const LifecycleHook = struct {
    name: []const u8,
    body: []const u8,
    is_ffi_wrapper: bool = false,
};

pub const BodyLine = struct {
    line: u32,
    text: []const u8,
};

pub const Component = struct {
    name: []const u8,
    state_vars: []StateVar,
    dom_nodes: []DomNode,
    root_nodes: []usize,
    handlers: []Handler,
    lifecycle_hooks: []LifecycleHook,
    route_pages: []RoutePage,
    release_vars: []const []const u8,
    orphan_lines: []BodyLine,
};

pub const SaxProgram = struct {
    arena: std.heap.ArenaAllocator,
    components: []Component,

    pub fn deinit(self: *SaxProgram) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

const tag_whitelist = struct {
    const layout = [_][]const u8{ "div", "section", "article", "header", "footer", "main", "nav", "aside" };
    const text = [_][]const u8{ "h1", "h2", "h3", "h4", "h5", "h6", "p", "span", "label", "strong", "em" };
    const inter = [_][]const u8{ "button", "input", "textarea", "select", "option", "form" };
    const list = [_][]const u8{ "ul", "ol", "li" };
    const media = [_][]const u8{ "img", "video", "canvas" };
    const table = [_][]const u8{ "table", "thead", "tbody", "tr", "th", "td" };
    const reserved = [_][]const u8{ "Router", "Page", "Slot", "Fragment", "React.Fragment" };

    fn contains(list_: []const []const u8, name: []const u8) bool {
        for (list_) |item| {
            if (std.mem.eql(u8, item, name)) return true;
        }
        return false;
    }

    fn valid(name: []const u8) bool {
        return contains(layout[0..], name) or
            contains(text[0..], name) or
            contains(inter[0..], name) or
            contains(list[0..], name) or
            contains(media[0..], name) or
            contains(table[0..], name) or
            contains(reserved[0..], name);
    }
};

const event_whitelist = [_][]const u8{
    "oncopy",
    "oncut",
    "onpaste",
    "oncompositionend",
    "oncompositionstart",
    "oncompositionupdate",
    "onbeforeinput",
    "onauxclick",
    "onclick",
    "oncontextmenu",
    "ondoubleclick",
    "ondrag",
    "ondragend",
    "ondragenter",
    "ondragexit",
    "ondragleave",
    "ondragover",
    "ondragstart",
    "ondrop",
    "onmousedown",
    "onmouseup",
    "onmousemove",
    "onmouseout",
    "onmouseover",
    "onmouseenter",
    "onmouseleave",
    "onpointerdown",
    "onpointermove",
    "onpointerup",
    "onpointercancel",
    "onpointerenter",
    "onpointerleave",
    "onpointerover",
    "onpointerout",
    "ongotpointercapture",
    "onlostpointercapture",
    "onscroll",
    "onscrollend",
    "onselect",
    "ontouchcancel",
    "ontouchend",
    "ontouchmove",
    "ontouchstart",
    "onwheel",
    "oninput",
    "onchange",
    "onsubmit",
    "onreset",
    "oninvalid",
    "onkeydown",
    "onkeypress",
    "onkeyup",
    "onfocus",
    "onblur",
    "onload",
    "onerror",
    "oncancel",
    "onclose",
    "ontoggle",
    "onabort",
    "oncanplay",
    "oncanplaythrough",
    "ondurationchange",
    "onemptied",
    "onencrypted",
    "onended",
    "onloadeddata",
    "onloadedmetadata",
    "onloadstart",
    "onpause",
    "onplay",
    "onplaying",
    "onprogress",
    "onratechange",
    "onseeked",
    "onseeking",
    "onstalled",
    "onsuspend",
    "ontimeupdate",
    "onvolumechange",
    "onwaiting",
    "onanimationstart",
    "onanimationend",
    "onanimationiteration",
    "ontransitionend",
};

const attr_whitelist = [_][]const u8{
    "class",
    "className",
    "style",
    "value",
    "defaultValue",
    "placeholder",
    "disabled",
    "required",
    "defaultChecked",
    "checked",
    "defaultSelected",
    "selected",
    "multiple",
    "type",
    "name",
    "for",
    "htmlFor",
    "tabIndex",
    "readOnly",
    "src",
    "alt",
    "title",
    "hidden",
    "id",
    "key",
    "ref",
    "width",
    "height",
    "renderer",
};

const dangerous_tags = [_][]const u8{
    "script",
    "iframe",
    "object",
    "embed",
    "template",
};

const dangerous_attrs = [_][]const u8{
    "innerHTML",
    "outerHTML",
    "dangerouslySetInnerHTML",
    "srcDoc",
};

const svg_pascal_tags = [_][]const u8{
    "svg",
    "path",
    "circle",
    "rect",
    "line",
    "polyline",
    "polygon",
    "ellipse",
    "g",
    "defs",
    "use",
    "symbol",
    "text",
    "tspan",
    "image",
    "mask",
    "pattern",
    "clipPath",
    "linearGradient",
    "radialGradient",
    "stop",
    "filter",
    "feBlend",
    "feColorMatrix",
    "feComponentTransfer",
    "feComposite",
    "feConvolveMatrix",
    "feDiffuseLighting",
    "feDisplacementMap",
    "feDistantLight",
    "feDropShadow",
    "feFlood",
    "feFuncA",
    "feFuncB",
    "feFuncG",
    "feFuncR",
    "feGaussianBlur",
    "feImage",
    "feMerge",
    "feMergeNode",
    "feMorphology",
    "feOffset",
    "fePointLight",
    "feSpecularLighting",
    "feSpotLight",
    "feTile",
    "feTurbulence",
    "foreignObject",
    "marker",
    "view",
};

const AttributeParseOptions = struct {
    allow_route_attrs: bool = false,
    allow_component_attrs: bool = false,
};

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn isWhitespaceOnly(text: []const u8) bool {
    for (text) |c| {
        if (!std.ascii.isWhitespace(c)) return false;
    }
    return true;
}

fn trimText(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r\n");
}

fn stripLeadingSpace(text: []const u8) []const u8 {
    return std.mem.trimLeft(u8, text, " \t");
}

fn splitLines(text: []const u8) std.mem.SplitIterator(u8, .scalar) {
    return std.mem.splitScalar(u8, text, '\n');
}

fn isSupportedEvent(name: []const u8) bool {
    for (event_whitelist) |item| {
        if (std.mem.eql(u8, item, name)) return true;
    }
    if (std.mem.startsWith(u8, name, "on") and std.mem.endsWith(u8, name, "capture")) {
        const base = name[0 .. name.len - "capture".len];
        for (event_whitelist) |item| {
            if (std.mem.eql(u8, item, base)) return true;
        }
    }
    return false;
}

fn isSupportedAttr(name: []const u8) bool {
    if (std.mem.startsWith(u8, name, "on")) return false;
    for (dangerous_attrs) |item| {
        if (std.mem.eql(u8, item, name)) return false;
    }
    if (std.mem.startsWith(u8, name, "aria-")) return true;
    if (std.mem.startsWith(u8, name, "data-")) return true;
    if (std.mem.indexOfScalar(u8, name, ':') != null) return std.mem.eql(u8, name, "xlink:href");
    return true;
}

fn isDangerousTag(name: []const u8) bool {
    for (dangerous_tags) |item| {
        if (std.mem.eql(u8, item, name)) return true;
    }
    return false;
}

fn isIntrinsicTag(name: []const u8) bool {
    if (tag_whitelist.valid(name)) return true;
    if (isDangerousTag(name)) return false;
    if (name.len == 0) return false;
    if (std.ascii.isLower(name[0])) return true;
    for (svg_pascal_tags) |item| {
        if (std.mem.eql(u8, item, name)) return true;
    }
    return false;
}

fn isUserComponentTag(name: []const u8) bool {
    if (name.len == 0) return false;
    if (tag_whitelist.valid(name)) return false;
    if (isDangerousTag(name)) return false;
    return std.ascii.isUpper(name[0]);
}

fn normalizeAttrName(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    if (std.mem.eql(u8, name, "className")) return allocator.dupe(u8, "class");
    if (std.mem.eql(u8, name, "htmlFor")) return allocator.dupe(u8, "for");
    if (std.mem.eql(u8, name, "defaultSelected")) return allocator.dupe(u8, "defaultSelected");
    if (std.mem.eql(u8, name, "autoFocus")) return allocator.dupe(u8, "autofocus");
    if (std.mem.eql(u8, name, "autoPlay")) return allocator.dupe(u8, "autoplay");
    if (std.mem.eql(u8, name, "playsInline")) return allocator.dupe(u8, "playsinline");
    if (std.mem.eql(u8, name, "autoComplete")) return allocator.dupe(u8, "autocomplete");
    if (std.mem.eql(u8, name, "acceptCharset")) return allocator.dupe(u8, "accept-charset");
    if (std.mem.eql(u8, name, "encType")) return allocator.dupe(u8, "enctype");
    if (std.mem.eql(u8, name, "formAction")) return allocator.dupe(u8, "formaction");
    if (std.mem.eql(u8, name, "formEncType")) return allocator.dupe(u8, "formenctype");
    if (std.mem.eql(u8, name, "formMethod")) return allocator.dupe(u8, "formmethod");
    if (std.mem.eql(u8, name, "formNoValidate")) return allocator.dupe(u8, "formnovalidate");
    if (std.mem.eql(u8, name, "formTarget")) return allocator.dupe(u8, "formtarget");
    if (std.mem.eql(u8, name, "dirName")) return allocator.dupe(u8, "dirname");
    if (std.mem.eql(u8, name, "accessKey")) return allocator.dupe(u8, "accesskey");
    if (std.mem.eql(u8, name, "tabIndex")) return allocator.dupe(u8, "tabindex");
    if (std.mem.eql(u8, name, "rowSpan")) return allocator.dupe(u8, "rowspan");
    if (std.mem.eql(u8, name, "colSpan")) return allocator.dupe(u8, "colspan");
    if (std.mem.eql(u8, name, "charSet")) return allocator.dupe(u8, "charset");
    if (std.mem.eql(u8, name, "httpEquiv")) return allocator.dupe(u8, "http-equiv");
    if (std.mem.eql(u8, name, "dateTime")) return allocator.dupe(u8, "datetime");
    if (std.mem.eql(u8, name, "inputMode")) return allocator.dupe(u8, "inputmode");
    if (std.mem.eql(u8, name, "enterKeyHint")) return allocator.dupe(u8, "enterkeyhint");
    if (std.mem.eql(u8, name, "autoCapitalize")) return allocator.dupe(u8, "autocapitalize");
    if (std.mem.eql(u8, name, "autoCorrect")) return allocator.dupe(u8, "autocorrect");
    if (std.mem.eql(u8, name, "maxLength")) return allocator.dupe(u8, "maxlength");
    if (std.mem.eql(u8, name, "minLength")) return allocator.dupe(u8, "minlength");
    if (std.mem.eql(u8, name, "noValidate")) return allocator.dupe(u8, "novalidate");
    if (std.mem.eql(u8, name, "readOnly")) return allocator.dupe(u8, "readonly");
    if (std.mem.eql(u8, name, "srcSet")) return allocator.dupe(u8, "srcset");
    if (std.mem.eql(u8, name, "srcLang")) return allocator.dupe(u8, "srclang");
    if (std.mem.eql(u8, name, "imageSrcSet")) return allocator.dupe(u8, "imagesrcset");
    if (std.mem.eql(u8, name, "imageSizes")) return allocator.dupe(u8, "imagesizes");
    if (std.mem.eql(u8, name, "longDesc")) return allocator.dupe(u8, "longdesc");
    if (std.mem.eql(u8, name, "hrefLang")) return allocator.dupe(u8, "hreflang");
    if (std.mem.eql(u8, name, "useMap")) return allocator.dupe(u8, "usemap");
    if (std.mem.eql(u8, name, "isMap")) return allocator.dupe(u8, "ismap");
    if (std.mem.eql(u8, name, "referrerPolicy")) return allocator.dupe(u8, "referrerpolicy");
    if (std.mem.eql(u8, name, "contentEditable")) return allocator.dupe(u8, "contenteditable");
    if (std.mem.eql(u8, name, "spellCheck")) return allocator.dupe(u8, "spellcheck");
    if (std.mem.eql(u8, name, "crossOrigin")) return allocator.dupe(u8, "crossorigin");
    if (std.mem.eql(u8, name, "itemProp")) return allocator.dupe(u8, "itemprop");
    if (std.mem.eql(u8, name, "itemScope")) return allocator.dupe(u8, "itemscope");
    if (std.mem.eql(u8, name, "itemType")) return allocator.dupe(u8, "itemtype");
    if (std.mem.eql(u8, name, "itemID")) return allocator.dupe(u8, "itemid");
    if (std.mem.eql(u8, name, "itemRef")) return allocator.dupe(u8, "itemref");
    if (std.mem.eql(u8, name, "accentHeight")) return allocator.dupe(u8, "accent-height");
    if (std.mem.eql(u8, name, "alignmentBaseline")) return allocator.dupe(u8, "alignment-baseline");
    if (std.mem.eql(u8, name, "baselineShift")) return allocator.dupe(u8, "baseline-shift");
    if (std.mem.eql(u8, name, "clipPath")) return allocator.dupe(u8, "clip-path");
    if (std.mem.eql(u8, name, "clipRule")) return allocator.dupe(u8, "clip-rule");
    if (std.mem.eql(u8, name, "colorInterpolation")) return allocator.dupe(u8, "color-interpolation");
    if (std.mem.eql(u8, name, "colorInterpolationFilters")) return allocator.dupe(u8, "color-interpolation-filters");
    if (std.mem.eql(u8, name, "colorRendering")) return allocator.dupe(u8, "color-rendering");
    if (std.mem.eql(u8, name, "dominantBaseline")) return allocator.dupe(u8, "dominant-baseline");
    if (std.mem.eql(u8, name, "enableBackground")) return allocator.dupe(u8, "enable-background");
    if (std.mem.eql(u8, name, "fillOpacity")) return allocator.dupe(u8, "fill-opacity");
    if (std.mem.eql(u8, name, "fillRule")) return allocator.dupe(u8, "fill-rule");
    if (std.mem.eql(u8, name, "floodColor")) return allocator.dupe(u8, "flood-color");
    if (std.mem.eql(u8, name, "floodOpacity")) return allocator.dupe(u8, "flood-opacity");
    if (std.mem.eql(u8, name, "fontFamily")) return allocator.dupe(u8, "font-family");
    if (std.mem.eql(u8, name, "fontSize")) return allocator.dupe(u8, "font-size");
    if (std.mem.eql(u8, name, "fontSizeAdjust")) return allocator.dupe(u8, "font-size-adjust");
    if (std.mem.eql(u8, name, "fontStretch")) return allocator.dupe(u8, "font-stretch");
    if (std.mem.eql(u8, name, "fontStyle")) return allocator.dupe(u8, "font-style");
    if (std.mem.eql(u8, name, "fontVariant")) return allocator.dupe(u8, "font-variant");
    if (std.mem.eql(u8, name, "fontWeight")) return allocator.dupe(u8, "font-weight");
    if (std.mem.eql(u8, name, "imageRendering")) return allocator.dupe(u8, "image-rendering");
    if (std.mem.eql(u8, name, "letterSpacing")) return allocator.dupe(u8, "letter-spacing");
    if (std.mem.eql(u8, name, "lightingColor")) return allocator.dupe(u8, "lighting-color");
    if (std.mem.eql(u8, name, "markerEnd")) return allocator.dupe(u8, "marker-end");
    if (std.mem.eql(u8, name, "markerMid")) return allocator.dupe(u8, "marker-mid");
    if (std.mem.eql(u8, name, "markerStart")) return allocator.dupe(u8, "marker-start");
    if (std.mem.eql(u8, name, "paintOrder")) return allocator.dupe(u8, "paint-order");
    if (std.mem.eql(u8, name, "pointerEvents")) return allocator.dupe(u8, "pointer-events");
    if (std.mem.eql(u8, name, "shapeRendering")) return allocator.dupe(u8, "shape-rendering");
    if (std.mem.eql(u8, name, "stopColor")) return allocator.dupe(u8, "stop-color");
    if (std.mem.eql(u8, name, "stopOpacity")) return allocator.dupe(u8, "stop-opacity");
    if (std.mem.eql(u8, name, "strokeDasharray")) return allocator.dupe(u8, "stroke-dasharray");
    if (std.mem.eql(u8, name, "strokeDashoffset")) return allocator.dupe(u8, "stroke-dashoffset");
    if (std.mem.eql(u8, name, "strokeLinecap")) return allocator.dupe(u8, "stroke-linecap");
    if (std.mem.eql(u8, name, "strokeLinejoin")) return allocator.dupe(u8, "stroke-linejoin");
    if (std.mem.eql(u8, name, "strokeMiterlimit")) return allocator.dupe(u8, "stroke-miterlimit");
    if (std.mem.eql(u8, name, "strokeOpacity")) return allocator.dupe(u8, "stroke-opacity");
    if (std.mem.eql(u8, name, "strokeWidth")) return allocator.dupe(u8, "stroke-width");
    if (std.mem.eql(u8, name, "textAnchor")) return allocator.dupe(u8, "text-anchor");
    if (std.mem.eql(u8, name, "textDecoration")) return allocator.dupe(u8, "text-decoration");
    if (std.mem.eql(u8, name, "textRendering")) return allocator.dupe(u8, "text-rendering");
    if (std.mem.eql(u8, name, "transformOrigin")) return allocator.dupe(u8, "transform-origin");
    if (std.mem.eql(u8, name, "unicodeBidi")) return allocator.dupe(u8, "unicode-bidi");
    if (std.mem.eql(u8, name, "vectorEffect")) return allocator.dupe(u8, "vector-effect");
    if (std.mem.eql(u8, name, "wordSpacing")) return allocator.dupe(u8, "word-spacing");
    if (std.mem.eql(u8, name, "writingMode")) return allocator.dupe(u8, "writing-mode");
    if (std.mem.eql(u8, name, "xlinkHref")) return allocator.dupe(u8, "xlink:href");
    if (std.mem.eql(u8, name, "xmlnsXlink")) return allocator.dupe(u8, "xmlns:xlink");
    if (std.mem.eql(u8, name, "onClick")) return allocator.dupe(u8, "onclick");
    if (std.mem.eql(u8, name, "onInput")) return allocator.dupe(u8, "oninput");
    if (std.mem.eql(u8, name, "onChange")) return allocator.dupe(u8, "onchange");
    if (std.mem.eql(u8, name, "onSubmit")) return allocator.dupe(u8, "onsubmit");
    if (std.mem.eql(u8, name, "onKeyDown")) return allocator.dupe(u8, "onkeydown");
    if (std.mem.eql(u8, name, "onKeyUp")) return allocator.dupe(u8, "onkeyup");
    if (std.mem.eql(u8, name, "onFocus")) return allocator.dupe(u8, "onfocus");
    if (std.mem.eql(u8, name, "onBlur")) return allocator.dupe(u8, "onblur");
    if (std.mem.eql(u8, name, "onMouseEnter")) return allocator.dupe(u8, "onmouseenter");
    if (std.mem.eql(u8, name, "onMouseLeave")) return allocator.dupe(u8, "onmouseleave");
    if (std.mem.startsWith(u8, name, "on") and name.len > 2 and std.ascii.isUpper(name[2])) {
        const out = try allocator.dupe(u8, name);
        for (out) |*c| c.* = std.ascii.toLower(c.*);
        return out;
    }
    return allocator.dupe(u8, name);
}

fn sanitizeName(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    for (text, 0..) |c, idx| {
        const valid = if (idx == 0) isIdentStart(c) else isIdentChar(c);
        try out.append(if (valid) c else '_');
    }
    if (out.items.len == 0) try out.appendSlice("node");
    if (!isIdentStart(out.items[0])) {
        try out.insert(0, 'n');
    }
    return try out.toOwnedSlice();
}

fn needsSanitizedAlias(text: []const u8) bool {
    for (text, 0..) |c, idx| {
        const valid = if (idx == 0) isIdentStart(c) else isIdentChar(c);
        if (!valid) return true;
    }
    return false;
}

fn lowercaseName(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    const out = try allocator.dupe(u8, text);
    for (out) |*c| c.* = std.ascii.toLower(c.*);
    return out;
}

fn inferStateType(init_expr: []const u8) ParseError!struct { ty: StateType, alloc_size: ?usize } {
    const trimmed = trimText(init_expr);
    if (trimmed.len == 0) return ParseError.InvalidStateInit;

    if (std.mem.startsWith(u8, trimmed, "alloc ")) {
        const size_text = trimText(trimmed["alloc ".len..]);
        if (size_text.len == 0) return ParseError.InvalidStateInit;
        const size = std.fmt.parseInt(usize, size_text, 10) catch return ParseError.InvalidStateInit;
        return .{ .ty = .ptr, .alloc_size = size };
    }

    if (std.mem.indexOf(u8, trimmed, " as ")) |idx| {
        const ty_text = trimText(trimmed[idx + 4 ..]);
        const ty = if (std.mem.eql(u8, ty_text, "i1")) StateType.i1 else if (std.mem.eql(u8, ty_text, "i32")) StateType.i32 else if (std.mem.eql(u8, ty_text, "i64")) StateType.i64 else if (std.mem.eql(u8, ty_text, "f64")) StateType.f64 else if (std.mem.eql(u8, ty_text, "ptr")) StateType.ptr else return ParseError.InvalidStateType;
        return .{ .ty = ty, .alloc_size = null };
    }

    if (std.mem.indexOfScalar(u8, trimmed, '.')) |_| {
        return .{ .ty = .f64, .alloc_size = null };
    }

    if (std.mem.eql(u8, trimmed, "0")) {
        return .{ .ty = .i64, .alloc_size = null };
    }

    _ = std.fmt.parseInt(i64, trimmed, 10) catch return ParseError.InvalidStateInit;
    return .{ .ty = .i64, .alloc_size = null };
}

fn parseTextPieces(allocator: std.mem.Allocator, raw_text: []const u8) ParseError![]TextPiece {
    const trimmed = trimText(raw_text);
    if (trimmed.len == 0) return &.{};

    var pieces = std.ArrayList(TextPiece).init(allocator);
    errdefer pieces.deinit();

    var cursor: usize = 0;
    while (cursor < trimmed.len) {
        const open = std.mem.indexOfScalarPos(u8, trimmed, cursor, '{') orelse {
            const tail = trimmed[cursor..];
            if (tail.len != 0) try pieces.append(.{ .text = try allocator.dupe(u8, tail) });
            break;
        };
        const head = trimmed[cursor..open];
        if (head.len != 0) try pieces.append(.{ .text = try allocator.dupe(u8, head) });
        const close = std.mem.indexOfScalarPos(u8, trimmed, open + 1, '}') orelse return ParseError.InvalidInterpolation;
        const expr = trimText(trimmed[open + 1 .. close]);
        if (expr.len == 0) return ParseError.InvalidInterpolation;
        try pieces.append(.{ .interpolation = try parseExpr(allocator, expr) });
        cursor = close + 1;
    }

    return try pieces.toOwnedSlice();
}

fn parseAttrValue(allocator: std.mem.Allocator, text: []const u8) ParseError!AttrValue {
    const trimmed = trimText(text);
    if (trimmed.len == 0) return ParseError.InvalidAttribute;
    if (trimmed[0] == '{' and trimmed[trimmed.len - 1] == '}') {
        const expr = trimText(trimmed[1 .. trimmed.len - 1]);
        if (expr.len == 0) return ParseError.InvalidInterpolation;
        return .{ .interpolation = try parseExpr(allocator, expr) };
    }
    if (std.mem.indexOfScalar(u8, trimmed, '{') != null or std.mem.indexOfScalar(u8, trimmed, '}') != null) {
        return .{ .template = try parseTextPieces(allocator, trimmed) };
    }
    return .{ .literal = try allocator.dupe(u8, trimmed) };
}

fn appendStyleKey(allocator: std.mem.Allocator, out: *std.ArrayList(u8), key: []const u8) ParseError!void {
    _ = allocator;
    if (key.len == 0) return ParseError.InvalidAttribute;
    for (key, 0..) |c, idx| {
        if (std.ascii.isUpper(c)) {
            if (idx != 0) try out.append('-');
            try out.append(std.ascii.toLower(c));
            continue;
        }
        if (c == '_') {
            try out.append('-');
            continue;
        }
        if (!std.ascii.isAlphanumeric(c) and c != '-') return ParseError.InvalidAttribute;
        try out.append(c);
    }
}

fn isUnsafeStyleValue(value: []const u8) bool {
    return std.ascii.indexOfIgnoreCase(value, "javascript:") != null or
        std.ascii.indexOfIgnoreCase(value, "expression(") != null;
}

fn isUnsafeInnerHtml(value: []const u8) bool {
    return std.ascii.indexOfIgnoreCase(value, "<script") != null or
        std.ascii.indexOfIgnoreCase(value, "</script") != null or
        std.ascii.indexOfIgnoreCase(value, "javascript:") != null or
        std.ascii.indexOfIgnoreCase(value, " onload") != null or
        std.ascii.indexOfIgnoreCase(value, " onclick") != null or
        std.ascii.indexOfIgnoreCase(value, " onerror") != null;
}

fn parseDangerouslySetInnerHtmlLiteral(allocator: std.mem.Allocator, text: []const u8) ParseError![]const u8 {
    const trimmed = trimText(text);
    if (trimmed.len == 0) return ParseError.InvalidAttribute;

    var pos: usize = 0;
    while (pos < trimmed.len and std.ascii.isWhitespace(trimmed[pos])) : (pos += 1) {}
    if (pos >= trimmed.len or !std.mem.startsWith(u8, trimmed[pos..], "__html")) return ParseError.InvalidAttribute;
    pos += "__html".len;
    while (pos < trimmed.len and std.ascii.isWhitespace(trimmed[pos])) : (pos += 1) {}
    if (pos >= trimmed.len or trimmed[pos] != ':') return ParseError.InvalidAttribute;
    pos += 1;
    while (pos < trimmed.len and std.ascii.isWhitespace(trimmed[pos])) : (pos += 1) {}
    if (pos >= trimmed.len or (trimmed[pos] != '"' and trimmed[pos] != '\'')) return ParseError.InvalidAttribute;

    const quote = trimmed[pos];
    pos += 1;
    const value_start = pos;
    while (pos < trimmed.len and trimmed[pos] != quote) : (pos += 1) {}
    if (pos >= trimmed.len) return ParseError.InvalidAttribute;
    const raw = trimmed[value_start..pos];
    pos += 1;
    while (pos < trimmed.len and std.ascii.isWhitespace(trimmed[pos])) : (pos += 1) {}
    if (pos < trimmed.len) {
        if (trimmed[pos] != ',') return ParseError.InvalidAttribute;
        pos += 1;
        while (pos < trimmed.len and std.ascii.isWhitespace(trimmed[pos])) : (pos += 1) {}
        if (pos < trimmed.len) return ParseError.InvalidAttribute;
    }
    if (raw.len == 0 or isUnsafeInnerHtml(raw)) return ParseError.InvalidAttribute;
    return try allocator.dupe(u8, raw);
}

fn appendJsonString(out: *std.ArrayList(u8), value: []const u8) ParseError!void {
    try out.append('"');
    for (value) |c| {
        if (c == '\n') {
            try out.appendSlice("\\n");
            continue;
        }
        if (c == '\r') {
            try out.appendSlice("\\r");
            continue;
        }
        if (c == '\t') {
            try out.appendSlice("\\t");
            continue;
        }
        if (c < 0x20) return ParseError.InvalidAttribute;
        switch (c) {
            '"', '\\' => {
                try out.append('\\');
                try out.append(c);
            },
            else => try out.append(c),
        }
    }
    try out.append('"');
}

fn skipComponentJsonWhitespace(text: []const u8, pos: *usize) void {
    while (pos.* < text.len and std.ascii.isWhitespace(text[pos.*])) : (pos.* += 1) {}
}

fn parseComponentJsonString(out: *std.ArrayList(u8), text: []const u8, pos: *usize) ParseError!void {
    if (pos.* >= text.len or (text[pos.*] != '"' and text[pos.*] != '\'')) return ParseError.InvalidAttribute;
    const quote = text[pos.*];
    pos.* += 1;
    const value_start = pos.*;
    while (pos.* < text.len and text[pos.*] != quote) : (pos.* += 1) {
        if (text[pos.*] == '\\') return ParseError.InvalidAttribute;
    }
    if (pos.* >= text.len) return ParseError.InvalidAttribute;
    try appendJsonString(out, text[value_start..pos.*]);
    pos.* += 1;
}

fn parseComponentJsonNumber(out: *std.ArrayList(u8), text: []const u8, pos: *usize) ParseError!void {
    const value_start = pos.*;
    while (pos.* < text.len) : (pos.* += 1) {
        const c = text[pos.*];
        if (!std.ascii.isDigit(c) and c != '-' and c != '+' and c != '.' and c != 'e' and c != 'E') break;
    }
    const value = text[value_start..pos.*];
    if (value.len == 0) return ParseError.InvalidAttribute;
    _ = std.fmt.parseFloat(f64, value) catch return ParseError.InvalidAttribute;
    try out.appendSlice(value);
}

fn parseComponentJsonArray(out: *std.ArrayList(u8), text: []const u8, pos: *usize) ParseError!void {
    if (pos.* >= text.len or text[pos.*] != '[') return ParseError.InvalidAttribute;
    pos.* += 1;
    try out.append('[');

    var wrote_any = false;
    while (true) {
        skipComponentJsonWhitespace(text, pos);
        if (pos.* >= text.len) return ParseError.InvalidAttribute;
        if (text[pos.*] == ']') {
            pos.* += 1;
            break;
        }
        if (wrote_any) try out.append(',');
        try parseComponentJsonValue(out, text, pos);
        wrote_any = true;
        skipComponentJsonWhitespace(text, pos);
        if (pos.* >= text.len) return ParseError.InvalidAttribute;
        if (text[pos.*] == ',') {
            pos.* += 1;
            continue;
        }
        if (text[pos.*] == ']') {
            pos.* += 1;
            break;
        }
        return ParseError.InvalidAttribute;
    }

    try out.append(']');
}

fn parseComponentJsonObjectKey(out: *std.ArrayList(u8), text: []const u8, pos: *usize) ParseError!void {
    if (pos.* >= text.len) return ParseError.InvalidAttribute;
    if (text[pos.*] == '[') {
        pos.* += 1;
        skipComponentJsonWhitespace(text, pos);
        try parseComponentJsonString(out, text, pos);
        skipComponentJsonWhitespace(text, pos);
        if (pos.* >= text.len or text[pos.*] != ']') return ParseError.InvalidAttribute;
        pos.* += 1;
        return;
    }
    if (text[pos.*] == '"' or text[pos.*] == '\'') {
        try parseComponentJsonString(out, text, pos);
        return;
    }
    const key_start = pos.*;
    if (!isIdentStart(text[pos.*])) return ParseError.InvalidAttribute;
    pos.* += 1;
    while (pos.* < text.len and isIdentChar(text[pos.*])) : (pos.* += 1) {}
    try appendJsonString(out, text[key_start..pos.*]);
}

fn parseComponentJsonObject(out: *std.ArrayList(u8), text: []const u8, pos: *usize, comptime has_braces: bool) ParseError!void {
    if (has_braces) {
        if (pos.* >= text.len or text[pos.*] != '{') return ParseError.InvalidAttribute;
        pos.* += 1;
    }
    try out.append('{');

    var wrote_any = false;
    while (true) {
        skipComponentJsonWhitespace(text, pos);
        if (has_braces) {
            if (pos.* >= text.len) return ParseError.InvalidAttribute;
            if (text[pos.*] == '}') {
                pos.* += 1;
                break;
            }
        } else if (pos.* >= text.len) {
            break;
        }

        if (std.mem.startsWith(u8, text[pos.*..], "...")) {
            pos.* += 3;
            skipComponentJsonWhitespace(text, pos);
            var spread = std.ArrayList(u8).init(out.allocator);
            defer spread.deinit();
            try parseComponentJsonObject(&spread, text, pos, true);
            if (spread.items.len < 2 or spread.items[0] != '{' or spread.items[spread.items.len - 1] != '}') return ParseError.InvalidAttribute;
            const inner = spread.items[1 .. spread.items.len - 1];
            if (inner.len != 0) {
                if (wrote_any) try out.append(',');
                try out.appendSlice(inner);
                wrote_any = true;
            }
        } else {
            if (wrote_any) try out.append(',');
            try parseComponentJsonObjectKey(out, text, pos);
            skipComponentJsonWhitespace(text, pos);
            if (pos.* >= text.len or text[pos.*] != ':') return ParseError.InvalidAttribute;
            pos.* += 1;
            try out.append(':');
            try parseComponentJsonValue(out, text, pos);
            wrote_any = true;
        }

        skipComponentJsonWhitespace(text, pos);
        if (has_braces) {
            if (pos.* >= text.len) return ParseError.InvalidAttribute;
            if (text[pos.*] == ',') {
                pos.* += 1;
                continue;
            }
            if (text[pos.*] == '}') {
                pos.* += 1;
                break;
            }
            return ParseError.InvalidAttribute;
        } else {
            if (pos.* >= text.len) break;
            if (text[pos.*] != ',') return ParseError.InvalidAttribute;
            pos.* += 1;
        }
    }

    try out.append('}');
}

fn parseComponentJsonValue(out: *std.ArrayList(u8), text: []const u8, pos: *usize) ParseError!void {
    skipComponentJsonWhitespace(text, pos);
    if (pos.* >= text.len) return ParseError.InvalidAttribute;
    if (text[pos.*] == '"' or text[pos.*] == '\'') {
        try parseComponentJsonString(out, text, pos);
        return;
    }
    if (text[pos.*] == '{') {
        try parseComponentJsonObject(out, text, pos, true);
        return;
    }
    if (text[pos.*] == '[') {
        try parseComponentJsonArray(out, text, pos);
        return;
    }
    if (std.mem.startsWith(u8, text[pos.*..], "true")) {
        pos.* += "true".len;
        try out.appendSlice("true");
        return;
    }
    if (std.mem.startsWith(u8, text[pos.*..], "false")) {
        pos.* += "false".len;
        try out.appendSlice("false");
        return;
    }
    if (std.mem.startsWith(u8, text[pos.*..], "null")) {
        pos.* += "null".len;
        try out.appendSlice("null");
        return;
    }
    try parseComponentJsonNumber(out, text, pos);
}

fn parseComponentObjectLiteral(allocator: std.mem.Allocator, text: []const u8) ParseError![]const u8 {
    const trimmed = trimText(text);
    if (trimmed.len == 0) return ParseError.InvalidAttribute;

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    var pos: usize = 0;
    try parseComponentJsonObject(&out, trimmed, &pos, false);
    skipComponentJsonWhitespace(trimmed, &pos);
    if (pos != trimmed.len) return ParseError.InvalidAttribute;
    return try out.toOwnedSlice();
}

fn appendTemplateText(allocator: std.mem.Allocator, pieces: *std.ArrayList(TextPiece), text: []const u8) ParseError!void {
    if (text.len == 0) return;
    if (pieces.items.len != 0) {
        switch (pieces.items[pieces.items.len - 1]) {
            .text => |prev| {
                const merged = try std.fmt.allocPrint(allocator, "{s}{s}", .{ prev, text });
                pieces.items[pieces.items.len - 1] = .{ .text = merged };
                return;
            },
            .interpolation, .json_string_interpolation, .json_object_spread => {},
        }
    }
    try pieces.append(.{ .text = try allocator.dupe(u8, text) });
}

fn appendTemplateJsonString(allocator: std.mem.Allocator, pieces: *std.ArrayList(TextPiece), value: []const u8) ParseError!void {
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    try appendJsonString(&out, value);
    try appendTemplateText(allocator, pieces, out.items);
}

fn parseComponentTemplateJsonString(allocator: std.mem.Allocator, pieces: *std.ArrayList(TextPiece), text: []const u8, pos: *usize) ParseError!void {
    if (pos.* >= text.len or (text[pos.*] != '"' and text[pos.*] != '\'')) return ParseError.InvalidAttribute;
    const quote = text[pos.*];
    pos.* += 1;
    const value_start = pos.*;
    while (pos.* < text.len and text[pos.*] != quote) : (pos.* += 1) {
        if (text[pos.*] == '\\') return ParseError.InvalidAttribute;
    }
    if (pos.* >= text.len) return ParseError.InvalidAttribute;
    try appendTemplateJsonString(allocator, pieces, text[value_start..pos.*]);
    pos.* += 1;
}

fn parseComponentTemplateJsonNumber(allocator: std.mem.Allocator, pieces: *std.ArrayList(TextPiece), text: []const u8, pos: *usize) ParseError!void {
    const value_start = pos.*;
    while (pos.* < text.len) : (pos.* += 1) {
        const c = text[pos.*];
        if (!std.ascii.isDigit(c) and c != '-' and c != '+' and c != '.' and c != 'e' and c != 'E') break;
    }
    const value = text[value_start..pos.*];
    if (value.len == 0) return ParseError.InvalidAttribute;
    _ = std.fmt.parseFloat(f64, value) catch return ParseError.InvalidAttribute;
    try appendTemplateText(allocator, pieces, value);
}

fn parseComponentTemplateJsonExprValue(allocator: std.mem.Allocator, pieces: *std.ArrayList(TextPiece), text: []const u8, pos: *usize) ParseError!void {
    const expr_start = pos.*;
    var quote: u8 = 0;
    var escaped = false;
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var brace_depth: usize = 0;
    while (pos.* < text.len) : (pos.* += 1) {
        const c = text[pos.*];
        if (quote != 0) {
            if (escaped) {
                escaped = false;
            } else if (c == '\\') {
                escaped = true;
            } else if (c == quote) {
                quote = 0;
            }
            continue;
        }
        if (c == '"' or c == '\'') {
            quote = c;
            continue;
        }
        switch (c) {
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth == 0) return ParseError.InvalidAttribute;
                paren_depth -= 1;
            },
            '[' => bracket_depth += 1,
            ']' => {
                if (paren_depth == 0 and bracket_depth == 0 and brace_depth == 0) break;
                if (bracket_depth == 0) return ParseError.InvalidAttribute;
                bracket_depth -= 1;
            },
            '{' => brace_depth += 1,
            '}' => {
                if (paren_depth == 0 and bracket_depth == 0 and brace_depth == 0) break;
                if (brace_depth == 0) return ParseError.InvalidAttribute;
                brace_depth -= 1;
            },
            ',' => if (paren_depth == 0 and bracket_depth == 0 and brace_depth == 0) break,
            else => {},
        }
    }
    if (quote != 0 or paren_depth != 0 or bracket_depth != 0 or brace_depth != 0) return ParseError.InvalidAttribute;
    const expr_text = trimText(text[expr_start..pos.*]);
    if (expr_text.len == 0) return ParseError.InvalidAttribute;
    try pieces.append(.{ .interpolation = try parseExpr(allocator, expr_text) });
}

fn parseComponentTemplateJsonValue(allocator: std.mem.Allocator, pieces: *std.ArrayList(TextPiece), text: []const u8, pos: *usize) ParseError!void {
    skipComponentJsonWhitespace(text, pos);
    if (pos.* >= text.len) return ParseError.InvalidAttribute;
    if (text[pos.*] == '"' or text[pos.*] == '\'') return parseComponentTemplateJsonString(allocator, pieces, text, pos);
    if (text[pos.*] == '{') return parseComponentTemplateJsonObject(allocator, pieces, text, pos, true);
    if (text[pos.*] == '[') return parseComponentTemplateJsonArray(allocator, pieces, text, pos);
    if (std.mem.startsWith(u8, text[pos.*..], "true")) {
        pos.* += "true".len;
        try appendTemplateText(allocator, pieces, "true");
        return;
    }
    if (std.mem.startsWith(u8, text[pos.*..], "false")) {
        pos.* += "false".len;
        try appendTemplateText(allocator, pieces, "false");
        return;
    }
    if (std.mem.startsWith(u8, text[pos.*..], "null")) {
        pos.* += "null".len;
        try appendTemplateText(allocator, pieces, "null");
        return;
    }
    if (isIdentStart(text[pos.*])) {
        return parseComponentTemplateJsonExprValue(allocator, pieces, text, pos);
    }
    try parseComponentTemplateJsonNumber(allocator, pieces, text, pos);
}

fn parseComponentTemplateJsonArray(allocator: std.mem.Allocator, pieces: *std.ArrayList(TextPiece), text: []const u8, pos: *usize) ParseError!void {
    if (pos.* >= text.len or text[pos.*] != '[') return ParseError.InvalidAttribute;
    pos.* += 1;
    try appendTemplateText(allocator, pieces, "[");
    var wrote_any = false;
    while (true) {
        skipComponentJsonWhitespace(text, pos);
        if (pos.* >= text.len) return ParseError.InvalidAttribute;
        if (text[pos.*] == ']') {
            pos.* += 1;
            break;
        }
        if (wrote_any) try appendTemplateText(allocator, pieces, ",");
        try parseComponentTemplateJsonValue(allocator, pieces, text, pos);
        wrote_any = true;
        skipComponentJsonWhitespace(text, pos);
        if (pos.* >= text.len) return ParseError.InvalidAttribute;
        if (text[pos.*] == ',') {
            pos.* += 1;
            continue;
        }
        if (text[pos.*] == ']') {
            pos.* += 1;
            break;
        }
        return ParseError.InvalidAttribute;
    }
    try appendTemplateText(allocator, pieces, "]");
}

fn parseComponentTemplateJsonObjectKey(allocator: std.mem.Allocator, pieces: *std.ArrayList(TextPiece), text: []const u8, pos: *usize) ParseError!void {
    if (pos.* >= text.len) return ParseError.InvalidAttribute;
    if (text[pos.*] == '[') {
        pos.* += 1;
        skipComponentJsonWhitespace(text, pos);
        if (pos.* < text.len and (text[pos.*] == '"' or text[pos.*] == '\'')) {
            try parseComponentTemplateJsonString(allocator, pieces, text, pos);
        } else {
            const key_start = pos.*;
            while (pos.* < text.len and text[pos.*] != ']') : (pos.* += 1) {}
            const expr_text = trimText(text[key_start..pos.*]);
            if (expr_text.len == 0) return ParseError.InvalidAttribute;
            try pieces.append(.{ .json_string_interpolation = try parseExpr(allocator, expr_text) });
        }
        skipComponentJsonWhitespace(text, pos);
        if (pos.* >= text.len or text[pos.*] != ']') return ParseError.InvalidAttribute;
        pos.* += 1;
        return;
    }
    if (text[pos.*] == '"' or text[pos.*] == '\'') return parseComponentTemplateJsonString(allocator, pieces, text, pos);
    const key_start = pos.*;
    if (!isIdentStart(text[pos.*])) return ParseError.InvalidAttribute;
    pos.* += 1;
    while (pos.* < text.len and isIdentChar(text[pos.*])) : (pos.* += 1) {}
    try appendTemplateJsonString(allocator, pieces, text[key_start..pos.*]);
}

fn appendComponentTemplateJsonSpreadLiteral(allocator: std.mem.Allocator, pieces: *std.ArrayList(TextPiece), text: []const u8, pos: *usize, wrote_any: bool) ParseError!bool {
    var spread_pieces = std.ArrayList(TextPiece).init(allocator);
    defer spread_pieces.deinit();
    try parseComponentTemplateJsonObject(allocator, &spread_pieces, text, pos, true);
    if (spread_pieces.items.len == 0) return ParseError.InvalidAttribute;

    var first_text: []const u8 = undefined;
    switch (spread_pieces.items[0]) {
        .text => |txt| first_text = txt,
        else => return ParseError.InvalidAttribute,
    }
    if (first_text.len == 0 or first_text[0] != '{') return ParseError.InvalidAttribute;

    const last_index = spread_pieces.items.len - 1;
    var last_text: []const u8 = undefined;
    switch (spread_pieces.items[last_index]) {
        .text => |txt| last_text = txt,
        else => return ParseError.InvalidAttribute,
    }
    if (last_text.len == 0 or last_text[last_text.len - 1] != '}') return ParseError.InvalidAttribute;

    var has_inner = false;
    for (spread_pieces.items, 0..) |piece, idx| {
        switch (piece) {
            .text => |txt| {
                var adjusted = txt;
                if (idx == 0) adjusted = adjusted[1..];
                if (idx == last_index) adjusted = adjusted[0 .. adjusted.len - 1];
                if (adjusted.len != 0) has_inner = true;
            },
            else => has_inner = true,
        }
    }
    if (!has_inner) return false;

    if (wrote_any) try appendTemplateText(allocator, pieces, ",");
    for (spread_pieces.items, 0..) |piece, idx| {
        switch (piece) {
            .text => |txt| {
                var adjusted = txt;
                if (idx == 0) adjusted = adjusted[1..];
                if (idx == last_index) adjusted = adjusted[0 .. adjusted.len - 1];
                try appendTemplateText(allocator, pieces, adjusted);
            },
            else => try pieces.append(piece),
        }
    }
    return true;
}

fn parseComponentTemplateJsonSpreadExpr(allocator: std.mem.Allocator, text: []const u8, pos: *usize) ParseError!Expr {
    const expr_start = pos.*;
    var quote: u8 = 0;
    var escaped = false;
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var brace_depth: usize = 0;
    while (pos.* < text.len) : (pos.* += 1) {
        const c = text[pos.*];
        if (quote != 0) {
            if (escaped) {
                escaped = false;
            } else if (c == '\\') {
                escaped = true;
            } else if (c == quote) {
                quote = 0;
            }
            continue;
        }
        if (c == '"' or c == '\'') {
            quote = c;
            continue;
        }
        switch (c) {
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth == 0) return ParseError.InvalidAttribute;
                paren_depth -= 1;
            },
            '[' => bracket_depth += 1,
            ']' => {
                if (bracket_depth == 0) return ParseError.InvalidAttribute;
                bracket_depth -= 1;
            },
            '{' => brace_depth += 1,
            '}' => {
                if (paren_depth == 0 and bracket_depth == 0 and brace_depth == 0) break;
                if (brace_depth == 0) return ParseError.InvalidAttribute;
                brace_depth -= 1;
            },
            ',' => if (paren_depth == 0 and bracket_depth == 0 and brace_depth == 0) break,
            else => {},
        }
    }
    if (quote != 0 or paren_depth != 0 or bracket_depth != 0 or brace_depth != 0) return ParseError.InvalidAttribute;
    const expr_text = trimText(text[expr_start..pos.*]);
    if (expr_text.len == 0) return ParseError.InvalidAttribute;
    return parseExpr(allocator, expr_text);
}

fn parseComponentTemplateJsonObject(allocator: std.mem.Allocator, pieces: *std.ArrayList(TextPiece), text: []const u8, pos: *usize, comptime has_braces: bool) ParseError!void {
    if (has_braces) {
        if (pos.* >= text.len or text[pos.*] != '{') return ParseError.InvalidAttribute;
        pos.* += 1;
    }
    try appendTemplateText(allocator, pieces, "{");
    var wrote_any = false;
    while (true) {
        skipComponentJsonWhitespace(text, pos);
        if (has_braces) {
            if (pos.* >= text.len) return ParseError.InvalidAttribute;
            if (text[pos.*] == '}') {
                pos.* += 1;
                break;
            }
        } else if (pos.* >= text.len) break;
        if (std.mem.startsWith(u8, text[pos.*..], "...")) {
            pos.* += 3;
            skipComponentJsonWhitespace(text, pos);
            if (pos.* < text.len and text[pos.*] == '{') {
                if (try appendComponentTemplateJsonSpreadLiteral(allocator, pieces, text, pos, wrote_any)) wrote_any = true;
            } else {
                const expr = try parseComponentTemplateJsonSpreadExpr(allocator, text, pos);
                try pieces.append(.{ .json_object_spread = .{
                    .expr = expr,
                    .prefix_comma = wrote_any,
                } });
                wrote_any = true;

                skipComponentJsonWhitespace(text, pos);
            }
        } else {
            if (wrote_any) try appendTemplateText(allocator, pieces, ",");
            try parseComponentTemplateJsonObjectKey(allocator, pieces, text, pos);
            skipComponentJsonWhitespace(text, pos);
            if (pos.* >= text.len or text[pos.*] != ':') return ParseError.InvalidAttribute;
            pos.* += 1;
            try appendTemplateText(allocator, pieces, ":");
            try parseComponentTemplateJsonValue(allocator, pieces, text, pos);
            wrote_any = true;
        }
        skipComponentJsonWhitespace(text, pos);
        if (has_braces) {
            if (pos.* >= text.len) return ParseError.InvalidAttribute;
            if (text[pos.*] == ',') {
                pos.* += 1;
                continue;
            }
            if (text[pos.*] == '}') {
                pos.* += 1;
                break;
            }
            return ParseError.InvalidAttribute;
        } else {
            if (pos.* >= text.len) break;
            if (text[pos.*] != ',') return ParseError.InvalidAttribute;
            pos.* += 1;
        }
    }
    try appendTemplateText(allocator, pieces, "}");
}

fn parseComponentObjectAttrValue(allocator: std.mem.Allocator, text: []const u8) ParseError!AttrValue {
    const trimmed = trimText(text);
    if (trimmed.len == 0) return ParseError.InvalidAttribute;
    var pieces = std.ArrayList(TextPiece).init(allocator);
    errdefer pieces.deinit();
    var pos: usize = 0;
    try parseComponentTemplateJsonObject(allocator, &pieces, trimmed, &pos, false);
    skipComponentJsonWhitespace(trimmed, &pos);
    if (pos != trimmed.len or pieces.items.len == 0) return ParseError.InvalidAttribute;
    if (pieces.items.len == 1) switch (pieces.items[0]) {
        .text => |txt| return .{ .literal = txt },
        .interpolation, .json_string_interpolation, .json_object_spread => {},
    };
    return .{ .template = try pieces.toOwnedSlice() };
}

pub fn parseComponentObjectLiteralJson(allocator: std.mem.Allocator, text: []const u8) ParseError![]const u8 {
    const trimmed = trimText(text);
    if (trimmed.len == 0) return ParseError.InvalidAttribute;

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    var pos: usize = 0;
    try parseComponentJsonObject(&out, trimmed, &pos, true);
    skipComponentJsonWhitespace(trimmed, &pos);
    if (pos != trimmed.len) return ParseError.InvalidAttribute;
    return try out.toOwnedSlice();
}

fn parseStyleObjectLiteral(allocator: std.mem.Allocator, text: []const u8) ParseError![]const u8 {
    const trimmed = trimText(text);
    if (trimmed.len == 0) return ParseError.InvalidAttribute;

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    var pos: usize = 0;
    while (pos < trimmed.len) {
        while (pos < trimmed.len and (std.ascii.isWhitespace(trimmed[pos]) or trimmed[pos] == ',')) : (pos += 1) {}
        if (pos >= trimmed.len) break;

        const key_start = pos;
        if (!isIdentStart(trimmed[pos])) return ParseError.InvalidAttribute;
        pos += 1;
        while (pos < trimmed.len and (isIdentChar(trimmed[pos]) or trimmed[pos] == '-')) : (pos += 1) {}
        const key = trimmed[key_start..pos];

        while (pos < trimmed.len and std.ascii.isWhitespace(trimmed[pos])) : (pos += 1) {}
        if (pos >= trimmed.len or trimmed[pos] != ':') return ParseError.InvalidAttribute;
        pos += 1;
        while (pos < trimmed.len and std.ascii.isWhitespace(trimmed[pos])) : (pos += 1) {}
        if (pos >= trimmed.len) return ParseError.InvalidAttribute;

        const value: []const u8 = if (trimmed[pos] == '"' or trimmed[pos] == '\'') value: {
            const quote = trimmed[pos];
            pos += 1;
            const value_start = pos;
            while (pos < trimmed.len and trimmed[pos] != quote) : (pos += 1) {}
            if (pos >= trimmed.len) return ParseError.InvalidAttribute;
            const raw = trimmed[value_start..pos];
            pos += 1;
            break :value raw;
        } else value: {
            const value_start = pos;
            while (pos < trimmed.len and trimmed[pos] != ',') : (pos += 1) {}
            break :value trimText(trimmed[value_start..pos]);
        };
        if (value.len == 0 or isUnsafeStyleValue(value)) return ParseError.InvalidAttribute;

        try appendStyleKey(allocator, &out, key);
        try out.appendSlice(": ");
        try out.appendSlice(value);
        try out.appendSlice("; ");

        while (pos < trimmed.len and std.ascii.isWhitespace(trimmed[pos])) : (pos += 1) {}
        if (pos < trimmed.len) {
            if (trimmed[pos] != ',') return ParseError.InvalidAttribute;
            pos += 1;
        }
    }

    if (out.items.len == 0) return ParseError.InvalidAttribute;
    return try out.toOwnedSlice();
}

fn parseExpr(allocator: std.mem.Allocator, expr: []const u8) ParseError!Expr {
    const expr_copy = try allocator.dupe(u8, expr);
    var deps = std.ArrayList([]const u8).init(allocator);
    errdefer deps.deinit();

    var tokens = std.mem.tokenizeAny(u8, expr, " \t\r\n()+-*/,%<>!&|^:=.");
    while (tokens.next()) |token| {
        if (!isIdentStart(token[0])) continue;
        var seen = false;
        for (deps.items) |dep| {
            if (std.mem.eql(u8, dep, token)) {
                seen = true;
                break;
            }
        }
        if (!seen) try deps.append(try allocator.dupe(u8, token));
    }

    return .{
        .expr = expr_copy,
        .deps = try deps.toOwnedSlice(),
    };
}

fn hasNativeEscape(text: []const u8) bool {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const trimmed = trimText(line);
        if (trimmed.len >= 2 and trimmed[0] == '$' and trimmed[trimmed.len - 1] == '$') return true;
    }
    return false;
}

const DomBuilder = struct {
    allocator: std.mem.Allocator,
    component_name: []const u8,
    nodes: std.ArrayList(DomNode),
    alias_counts: std.StringHashMap(usize),

    fn init(allocator: std.mem.Allocator, component_name: []const u8) DomBuilder {
        return .{
            .allocator = allocator,
            .component_name = component_name,
            .nodes = std.ArrayList(DomNode).init(allocator),
            .alias_counts = std.StringHashMap(usize).init(allocator),
        };
    }

    fn deinit(self: *DomBuilder) void {
        self.nodes.deinit();
        self.alias_counts.deinit();
    }

    fn makeAlias(self: *DomBuilder, base: []const u8) ![]const u8 {
        const key = try self.allocator.dupe(u8, base);
        errdefer self.allocator.free(key);
        const count = self.alias_counts.get(key) orelse 0;
        try self.alias_counts.put(key, count + 1);
        if (count == 0) return key;
        return try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ key, count });
    }

    fn takeNodes(self: *DomBuilder) ![]DomNode {
        return try self.nodes.toOwnedSlice();
    }
};

const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    line: u32 = 1,
    col: u32 = 1,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Parser {
        return .{ .allocator = allocator, .source = source };
    }

    pub fn parse(self: *Parser) ParseError!SaxProgram {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer arena.deinit();
        const a = arena.allocator();

        var components = std.ArrayList(Component).init(a);
        errdefer components.deinit();

        var pos: usize = 0;
        while (true) {
            self.skipWhitespaceAndComments(&pos);
            if (pos >= self.source.len) break;
            const component = try self.parseComponent(a, &pos);
            try components.append(component);
        }

        return .{
            .arena = arena,
            .components = try components.toOwnedSlice(),
        };
    }

    fn parseComponent(self: *Parser, allocator: std.mem.Allocator, pos: *usize) ParseError!Component {
        try self.expectString(pos, "<Component");
        self.skipInlineSpace(pos);
        try self.expectString(pos, "name");
        self.skipInlineSpace(pos);
        try self.expectChar(pos, '=');
        self.skipInlineSpace(pos);
        const name = try self.parseQuotedIdent(allocator, pos);
        try self.expectChar(pos, '>');

        var state_vars = std.ArrayList(StateVar).init(allocator);
        defer state_vars.deinit();
        var state_names = std.StringHashMap(void).init(allocator);
        defer state_names.deinit();

        var dom_builder = DomBuilder.init(allocator, name);
        defer dom_builder.deinit();

        var handlers = std.ArrayList(Handler).init(allocator);
        defer handlers.deinit();
        var handler_names = std.StringHashMap(void).init(allocator);
        defer handler_names.deinit();

        var lifecycle_hooks = std.ArrayList(LifecycleHook).init(allocator);
        defer lifecycle_hooks.deinit();
        var lifecycle_names = std.StringHashMap(void).init(allocator);
        defer lifecycle_names.deinit();

        var route_pages = std.ArrayList(RoutePage).init(allocator);
        defer route_pages.deinit();

        var release_vars = std.ArrayList([]const u8).init(allocator);
        defer release_vars.deinit();

        var orphan_lines = std.ArrayList(BodyLine).init(allocator);
        defer orphan_lines.deinit();

        self.skipWhitespaceAndComments(pos);
        if (self.peekString(pos, "<state>")) {
            try self.parseStateBlock(allocator, pos, &state_vars, &state_names);
        }

        self.skipWhitespaceAndComments(pos);
        const dom_start = pos.*;
        while (pos.* < self.source.len) {
            self.skipWhitespaceAndComments(pos);
            if (pos.* >= self.source.len) break;
            if (self.peekString(pos, "</Component>")) break;
            const line = self.peekLine(pos);
            const trimmed = stripLeadingSpace(line);
            if (trimmed.len != 0 and (trimmed[0] == '@' or trimmed[0] == '!')) break;
            self.advanceLine(pos);
        }
        const dom_end = pos.*;
        const dom_text = self.source[dom_start..dom_end];
        try self.parseDomChunk(allocator, &dom_builder, &route_pages, dom_text);

        while (true) {
            self.skipWhitespaceAndComments(pos);
            if (pos.* >= self.source.len) break;
            if (self.peekString(pos, "</Component>")) break;
            const line = self.peekLine(pos);
            const trimmed = stripLeadingSpace(line);
            if (trimmed.len == 0) {
                self.advanceLine(pos);
                continue;
            }
            if (trimmed[0] == '@') {
                const handler = try self.parseHandler(allocator, pos);
                if (!handler.is_ffi_wrapper and hasNativeEscape(handler.body)) return ParseError.InvalidNativeEscape;
                if (std.mem.eql(u8, handler.name, "onMount") or
                    std.mem.eql(u8, handler.name, "onUnmount") or
                    std.mem.eql(u8, handler.name, "onUpdate"))
                {
                    if (lifecycle_names.contains(handler.name)) return ParseError.DuplicateHandler;
                    try lifecycle_names.put(try allocator.dupe(u8, handler.name), {});
                    try lifecycle_hooks.append(.{ .name = handler.name, .body = handler.body, .is_ffi_wrapper = handler.is_ffi_wrapper });
                } else {
                    if (handler_names.contains(handler.name)) return ParseError.DuplicateHandler;
                    try handler_names.put(try allocator.dupe(u8, handler.name), {});
                    try handlers.append(handler);
                }
                continue;
            }
            if (trimmed[0] == '!') {
                try self.parseReleaseLines(allocator, pos, &release_vars);
                continue;
            }

            if (hasNativeEscape(trimmed)) return ParseError.InvalidNativeEscape;

            try orphan_lines.append(.{
                .line = self.line,
                .text = try allocator.dupe(u8, line),
            });
            self.advanceLine(pos);
        }

        self.skipWhitespaceAndComments(pos);
        try self.expectString(pos, "</Component>");

        // Validate DOM and handler references.
        var node_aliases = std.StringHashMap(void).init(allocator);
        defer node_aliases.deinit();
        for (dom_builder.nodes.items) |node| {
            _ = try node_aliases.put(node.alias, {});
            for (node.attrs) |attr| {
                if (!std.mem.eql(u8, attr.name, "ref")) continue;
                const expr = switch (attr.value) {
                    .interpolation => |expr| expr,
                    else => return ParseError.InvalidAttribute,
                };
                const ref_name = expr.expr;
                var found_ref = false;
                for (state_vars.items) |sv| {
                    if (!std.mem.eql(u8, sv.name, ref_name)) continue;
                    const expected_ty: StateType = if (node.is_user_component) .ptr else .i64;
                    if (sv.ty != expected_ty) return ParseError.InvalidAttribute;
                    found_ref = true;
                    break;
                }
                if (!found_ref and handler_names.contains(ref_name)) found_ref = true;
                if (!found_ref) return ParseError.InvalidAttribute;
            }
        }

        // releases must refer to declared state vars.
        for (release_vars.items) |release_name| {
            if (!state_names.contains(release_name)) return ParseError.InvalidRelease;
        }

        const root_nodes = try self.copyRootNodes(allocator, dom_builder.nodes.items);
        const dom_nodes = try dom_builder.nodes.toOwnedSlice();

        return .{
            .name = try allocator.dupe(u8, name),
            .state_vars = try state_vars.toOwnedSlice(),
            .dom_nodes = dom_nodes,
            .root_nodes = root_nodes,
            .handlers = try handlers.toOwnedSlice(),
            .lifecycle_hooks = try lifecycle_hooks.toOwnedSlice(),
            .route_pages = try route_pages.toOwnedSlice(),
            .release_vars = try release_vars.toOwnedSlice(),
            .orphan_lines = try orphan_lines.toOwnedSlice(),
        };
    }

    fn copyRootNodes(
        self: *Parser,
        allocator: std.mem.Allocator,
        nodes: []const DomNode,
    ) ParseError![]usize {
        _ = self;
        var roots = std.ArrayList(usize).init(allocator);
        defer roots.deinit();
        for (nodes, 0..) |_, idx| {
            var is_child = false;
            for (nodes) |candidate| {
                for (candidate.children) |child| {
                    switch (child) {
                        .node_index => |child_idx| {
                            if (child_idx == idx) is_child = true;
                        },
                        else => {},
                    }
                }
            }
            if (!is_child) try roots.append(idx);
        }
        return try roots.toOwnedSlice();
    }

    fn parseStateBlock(
        self: *Parser,
        allocator: std.mem.Allocator,
        pos: *usize,
        state_vars: *std.ArrayList(StateVar),
        state_names: *std.StringHashMap(void),
    ) ParseError!void {
        try self.expectString(pos, "<state>");
        while (true) {
            self.skipWhitespaceAndComments(pos);
            if (self.peekString(pos, "</state>")) {
                try self.expectString(pos, "</state>");
                break;
            }
            const line = trimText(self.peekLine(pos));
            if (line.len == 0) {
                self.advanceLine(pos);
                continue;
            }
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse return ParseError.InvalidStateVar;
            const name = trimText(line[0..eq]);
            const expr = trimText(line[eq + 1 ..]);
            if (name.len == 0 or expr.len == 0) return ParseError.InvalidStateVar;
            if (!isIdentStart(name[0])) return ParseError.InvalidStateVar;
            for (name[1..]) |c| {
                if (!isIdentChar(c)) return ParseError.InvalidStateVar;
            }
            if (state_names.contains(name)) return ParseError.DuplicateStateVar;
            try state_names.put(name, {});
            const init_info = try inferStateType(expr);
            try state_vars.append(.{
                .name = try allocator.dupe(u8, name),
                .init_expr = try allocator.dupe(u8, expr),
                .ty = init_info.ty,
                .alloc_size = init_info.alloc_size,
            });
            self.advanceLine(pos);
        }
    }

    fn parseDomChunk(self: *Parser, allocator: std.mem.Allocator, builder: *DomBuilder, route_pages: *std.ArrayList(RoutePage), chunk: []const u8) ParseError!void {
        var pos: usize = 0;
        while (pos < chunk.len) {
            self.skipChunkWhitespace(chunk, &pos);
            if (pos >= chunk.len) break;
            if (chunk[pos] != '<') {
                const text_start = pos;
                while (pos < chunk.len and chunk[pos] != '<') : (pos += 1) {}
                const pieces = try parseTextPieces(allocator, chunk[text_start..pos]);
                if (pieces.len != 0 and !isWhitespaceOnly(chunk[text_start..pos])) return ParseError.InvalidComponentBody;
                continue;
            }
            const node_index = try self.parseDomNode(allocator, builder, route_pages, chunk, &pos);
            _ = node_index;
        }
    }

    fn parseDomNode(self: *Parser, allocator: std.mem.Allocator, builder: *DomBuilder, route_pages: *std.ArrayList(RoutePage), chunk: []const u8, pos: *usize) ParseError!usize {
        try self.expectChunkChar(chunk, pos, '<');
        if (pos.* < chunk.len and chunk[pos.*] == '/') return ParseError.InvalidDOMTag;

        const shorthand_fragment = pos.* < chunk.len and chunk[pos.*] == '>';
        const tag = if (shorthand_fragment) tag: {
            pos.* += 1;
            break :tag try allocator.dupe(u8, "Fragment");
        } else try self.parseChunkIdent(allocator, chunk, pos);
        const is_intrinsic = isIntrinsicTag(tag);
        const is_user_component = isUserComponentTag(tag);
        if (!is_intrinsic and !is_user_component) return ParseError.UnknownTag;
        if (std.mem.eql(u8, tag, "Router")) {
            try self.parseRouterBlock(allocator, route_pages, chunk, pos);
            return builder.nodes.items.len;
        }
        if (std.mem.eql(u8, tag, "Page")) return ParseError.InvalidPage;
        const alias = if (needsSanitizedAlias(tag)) try sanitizeName(allocator, tag) else try builder.makeAlias(tag);

        var attrs = std.ArrayList(Attribute).init(allocator);
        defer attrs.deinit();
        var node_key: ?Expr = null;

        if (!shorthand_fragment) {
            while (true) {
                self.skipChunkInlineSpace(chunk, pos);
                if (pos.* >= chunk.len) return ParseError.UnexpectedEOF;
                if (chunk[pos.*] == '/') {
                    pos.* += 1;
                    try self.expectChunkChar(chunk, pos, '>');
                    try builder.nodes.append(.{
                        .tag = try allocator.dupe(u8, tag),
                        .attrs = try attrs.toOwnedSlice(),
                        .children = try allocator.alloc(DomChild, 0),
                        .self_closing = true,
                        .alias = try allocator.dupe(u8, alias),
                        .key = node_key,
                        .is_user_component = is_user_component,
                    });
                    return builder.nodes.items.len - 1;
                }
                if (chunk[pos.*] == '>') {
                    pos.* += 1;
                    break;
                }

                const attr = try self.parseAttribute(allocator, chunk, pos, .{ .allow_component_attrs = is_user_component });
                if (std.mem.eql(u8, attr.name, "key")) {
                    if (node_key != null) return ParseError.InvalidAttribute;
                    node_key = switch (attr.value) {
                        .interpolation => |expr| expr,
                        else => return ParseError.InvalidAttribute,
                    };
                    continue;
                }
                try attrs.append(attr);
            }
        }

        try builder.nodes.append(.{
            .tag = try allocator.dupe(u8, tag),
            .attrs = try attrs.toOwnedSlice(),
            .children = try allocator.alloc(DomChild, 0),
            .self_closing = false,
            .alias = try allocator.dupe(u8, alias),
            .key = node_key,
            .is_user_component = is_user_component,
        });
        const idx = builder.nodes.items.len - 1;

        var children = std.ArrayList(DomChild).init(allocator);
        defer children.deinit();

        while (pos.* < chunk.len) {
            self.skipChunkWhitespace(chunk, pos);
            if (pos.* >= chunk.len) break;
            if (chunk[pos.*] == '<' and pos.* + 1 < chunk.len and chunk[pos.* + 1] == '/') {
                pos.* += 2;
                const close_tag = if (pos.* < chunk.len and chunk[pos.*] == '>') close: {
                    pos.* += 1;
                    break :close "Fragment";
                } else close: {
                    const parsed = try self.parseChunkIdent(allocator, chunk, pos);
                    self.skipChunkInlineSpace(chunk, pos);
                    try self.expectChunkChar(chunk, pos, '>');
                    break :close parsed;
                };
                if (!std.mem.eql(u8, close_tag, tag)) return ParseError.InvalidDOMTag;
                break;
            }

            if (chunk[pos.*] == '<') {
                const child_idx = try self.parseDomNode(allocator, builder, route_pages, chunk, pos);
                try children.append(.{ .node_index = child_idx });
                continue;
            }

            const text_start = pos.*;
            while (pos.* < chunk.len and chunk[pos.*] != '<') : (pos.* += 1) {}
            const pieces = try parseTextPieces(allocator, chunk[text_start..pos.*]);
            for (pieces) |piece| {
                try children.append(.{ .text = piece });
            }
        }

        builder.nodes.items[idx].children = try children.toOwnedSlice();
        return idx;
    }

    fn parseRouterBlock(self: *Parser, allocator: std.mem.Allocator, route_pages: *std.ArrayList(RoutePage), chunk: []const u8, pos: *usize) ParseError!void {
        self.skipChunkInlineSpace(chunk, pos);
        if (pos.* < chunk.len and chunk[pos.*] == '/') return ParseError.InvalidRouter;
        if (pos.* >= chunk.len or chunk[pos.*] != '>') return ParseError.InvalidRouter;
        pos.* += 1;

        while (pos.* < chunk.len) {
            self.skipChunkWhitespace(chunk, pos);
            if (pos.* >= chunk.len) return ParseError.UnexpectedEOF;
            if (chunk[pos.*] == '<' and pos.* + 1 < chunk.len and chunk[pos.* + 1] == '/') {
                pos.* += 2;
                const close_tag = try self.parseChunkIdent(allocator, chunk, pos);
                if (!std.mem.eql(u8, close_tag, "Router")) return ParseError.InvalidRouter;
                self.skipChunkInlineSpace(chunk, pos);
                try self.expectChunkChar(chunk, pos, '>');
                return;
            }
            if (chunk[pos.*] != '<') return ParseError.InvalidRouter;
            try self.parsePageNode(allocator, route_pages, chunk, pos);
        }
        return ParseError.UnexpectedEOF;
    }

    fn parsePageNode(self: *Parser, allocator: std.mem.Allocator, route_pages: *std.ArrayList(RoutePage), chunk: []const u8, pos: *usize) ParseError!void {
        try self.expectChunkChar(chunk, pos, '<');
        const tag = try self.parseChunkIdent(allocator, chunk, pos);
        if (!std.mem.eql(u8, tag, "Page")) return ParseError.InvalidPage;

        var path: ?[]const u8 = null;
        var component: ?[]const u8 = null;

        while (true) {
            self.skipChunkInlineSpace(chunk, pos);
            if (pos.* >= chunk.len) return ParseError.UnexpectedEOF;
            if (chunk[pos.*] == '/') {
                pos.* += 1;
                try self.expectChunkChar(chunk, pos, '>');
                if (path == null or component == null) return ParseError.InvalidPage;
                try route_pages.append(.{ .path = try allocator.dupe(u8, path.?), .component = try allocator.dupe(u8, component.?) });
                return;
            }
            if (chunk[pos.*] == '>') return ParseError.InvalidPage;

            const attr = try self.parseAttribute(allocator, chunk, pos, .{ .allow_route_attrs = true });
            if (attr.is_event) return ParseError.InvalidPage;
            const value = switch (attr.value) {
                .literal => |lit| lit,
                .interpolation => return ParseError.InvalidPage,
                .template => return ParseError.InvalidPage,
            };
            if (std.mem.eql(u8, attr.name, "path")) {
                path = value;
            } else if (std.mem.eql(u8, attr.name, "component")) {
                component = value;
            } else {
                return ParseError.InvalidPage;
            }
        }
    }

    fn parseAttribute(
        self: *Parser,
        allocator: std.mem.Allocator,
        chunk: []const u8,
        pos: *usize,
        options: AttributeParseOptions,
    ) ParseError!Attribute {
        const raw_name = try self.parseChunkIdent(allocator, chunk, pos);
        const name = try normalizeAttrName(allocator, raw_name);
        self.skipChunkInlineSpace(chunk, pos);

        if (pos.* >= chunk.len) return ParseError.UnexpectedEOF;
        if (chunk[pos.*] != '=') {
            if (options.allow_route_attrs) return ParseError.InvalidPage;
            if (isSupportedEvent(name)) return ParseError.InvalidEventName;
            if (std.mem.startsWith(u8, name, "on")) return ParseError.UnknownEvent;
            if (!options.allow_component_attrs and !isSupportedAttr(name)) return ParseError.InvalidAttribute;
            return .{ .name = name, .value = .{ .literal = try allocator.dupe(u8, "1") } };
        }

        try self.expectChunkChar(chunk, pos, '=');
        self.skipChunkInlineSpace(chunk, pos);

        if (pos.* >= chunk.len) return ParseError.UnexpectedEOF;
        if (chunk[pos.*] == '"') {
            pos.* += 1;
            const start = pos.*;
            while (pos.* < chunk.len and chunk[pos.*] != '"') : (pos.* += 1) {}
            if (pos.* >= chunk.len) return ParseError.UnexpectedEOF;
            const raw = chunk[start..pos.*];
            pos.* += 1;
            if (!options.allow_route_attrs and !options.allow_component_attrs and !isSupportedAttr(name)) return ParseError.InvalidAttribute;
            const value = try parseAttrValue(allocator, raw);
            return .{ .name = name, .value = value };
        }

        if (chunk[pos.*] == '{') {
            if (std.mem.eql(u8, name, "dangerouslySetInnerHTML") and pos.* + 1 < chunk.len and chunk[pos.* + 1] == '{') {
                if (options.allow_route_attrs or options.allow_component_attrs) return ParseError.InvalidAttribute;
                pos.* += 2;
                const start = pos.*;
                while (pos.* + 1 < chunk.len and !(chunk[pos.*] == '}' and chunk[pos.* + 1] == '}')) : (pos.* += 1) {}
                if (pos.* + 1 >= chunk.len) return ParseError.UnexpectedEOF;
                const raw = chunk[start..pos.*];
                pos.* += 2;
                return .{ .name = name, .value = .{ .literal = try parseDangerouslySetInnerHtmlLiteral(allocator, raw) } };
            }
            if (std.mem.eql(u8, name, "style") and pos.* + 1 < chunk.len and chunk[pos.* + 1] == '{') {
                if (options.allow_route_attrs) return ParseError.InvalidPage;
                if (!options.allow_component_attrs and !isSupportedAttr(name)) return ParseError.InvalidAttribute;
                pos.* += 2;
                const start = pos.*;
                while (pos.* + 1 < chunk.len and !(chunk[pos.*] == '}' and chunk[pos.* + 1] == '}')) : (pos.* += 1) {}
                if (pos.* + 1 >= chunk.len) return ParseError.UnexpectedEOF;
                const raw = chunk[start..pos.*];
                pos.* += 2;
                return .{ .name = name, .value = .{ .literal = try parseStyleObjectLiteral(allocator, raw) } };
            }
            if (options.allow_component_attrs and pos.* + 1 < chunk.len and chunk[pos.* + 1] == '{') {
                pos.* += 2;
                const start = pos.*;
                while (pos.* + 1 < chunk.len and !(chunk[pos.*] == '}' and chunk[pos.* + 1] == '}')) : (pos.* += 1) {}
                if (pos.* + 1 >= chunk.len) return ParseError.UnexpectedEOF;
                const raw = chunk[start..pos.*];
                pos.* += 2;
                return .{ .name = name, .value = try parseComponentObjectAttrValue(allocator, raw), .is_object_prop = true };
            }

            pos.* += 1;
            const start = pos.*;
            while (pos.* < chunk.len and chunk[pos.*] != '}') : (pos.* += 1) {}
            if (pos.* >= chunk.len) return ParseError.UnexpectedEOF;
            const raw = trimText(chunk[start..pos.*]);
            pos.* += 1;
            if (isSupportedEvent(name)) {
                const handler = if (std.mem.startsWith(u8, raw, "^")) trimText(raw[1..]) else raw;
                if (handler.len == 0) return ParseError.InvalidEventName;
                if (!isIdentStart(handler[0])) return ParseError.InvalidEventName;
                for (handler[1..]) |c| {
                    if (!isIdentChar(c)) return ParseError.InvalidEventName;
                }
                return .{
                    .name = name,
                    .value = .{ .literal = try allocator.dupe(u8, "") },
                    .is_event = true,
                    .event_handler = try allocator.dupe(u8, handler),
                };
            }
            if (std.mem.startsWith(u8, name, "on")) return ParseError.UnknownEvent;
            if (options.allow_route_attrs) return ParseError.InvalidPage;
            if (!options.allow_component_attrs and !isSupportedAttr(name)) return ParseError.InvalidAttribute;
            if (raw.len == 0) return ParseError.InvalidInterpolation;
            return .{ .name = name, .value = .{ .interpolation = try parseExpr(allocator, raw) } };
        }

        return ParseError.InvalidAttribute;
    }

    fn parseHandler(self: *Parser, allocator: std.mem.Allocator, pos: *usize) ParseError!Handler {
        const header = trimText(self.peekLine(pos));
        if (header.len < 3 or header[0] != '@' or header[header.len - 1] != ':') return ParseError.InvalidHandler;
        var name = trimText(header[1 .. header.len - 1]);
        var is_ffi_wrapper = false;
        if (std.mem.startsWith(u8, name, "ffi_wrapper")) {
            if (name.len == "ffi_wrapper".len) return ParseError.InvalidHandler;
            const next = name["ffi_wrapper".len];
            if (std.ascii.isWhitespace(next)) {
                const after = trimText(name["ffi_wrapper".len..]);
                if (after.len == 0) return ParseError.InvalidHandler;
                name = after;
                is_ffi_wrapper = true;
            }
        }
        if (!isIdentStart(name[0])) return ParseError.InvalidHandler;
        for (name[1..]) |c| {
            if (!isIdentChar(c)) return ParseError.InvalidHandler;
        }

        self.advanceLine(pos);
        const body_start = pos.*;
        while (pos.* < self.source.len) {
            const line = trimText(self.peekLine(pos));
            if (line.len == 0) {
                self.advanceLine(pos);
                continue;
            }
            if ((line[0] == '@' and line[line.len - 1] == ':') or line[0] == '!') break;
            if (self.peekString(pos, "</Component>")) break;
            self.advanceLine(pos);
        }
        const body = self.source[body_start..pos.*];
        return .{
            .name = try allocator.dupe(u8, name),
            .body = try allocator.dupe(u8, body),
            .is_ffi_wrapper = is_ffi_wrapper,
        };
    }

    fn parseReleaseLines(self: *Parser, allocator: std.mem.Allocator, pos: *usize, out: *std.ArrayList([]const u8)) ParseError!void {
        while (pos.* < self.source.len) {
            const line = trimText(self.peekLine(pos));
            if (line.len == 0) {
                self.advanceLine(pos);
                continue;
            }
            if (line[0] != '!') break;
            var cursor: usize = 0;
            while (cursor < line.len) {
                while (cursor < line.len and std.ascii.isWhitespace(line[cursor])) : (cursor += 1) {}
                if (cursor >= line.len) break;
                if (line[cursor] != '!') return ParseError.InvalidRelease;
                cursor += 1;
                const start = cursor;
                while (cursor < line.len and isIdentChar(line[cursor])) : (cursor += 1) {}
                const name = line[start..cursor];
                if (name.len == 0) return ParseError.InvalidRelease;
                try out.append(try allocator.dupe(u8, name));
            }
            self.advanceLine(pos);
            if (self.peekString(pos, "</Component>")) break;
        }
    }

    fn peekLine(self: *Parser, pos: *const usize) []const u8 {
        var end = pos.*;
        while (end < self.source.len and self.source[end] != '\n') : (end += 1) {}
        return self.source[pos.*..end];
    }

    fn advanceLine(self: *Parser, pos: *usize) void {
        while (pos.* < self.source.len and self.source[pos.*] != '\n') : (pos.* += 1) {}
        if (pos.* < self.source.len and self.source[pos.*] == '\n') {
            pos.* += 1;
            self.line += 1;
            self.col = 1;
        }
        self.skipWhitespaceAndComments(pos);
    }

    fn skipWhitespaceAndComments(self: *Parser, pos: *usize) void {
        while (pos.* < self.source.len) {
            const ch = self.source[pos.*];
            if (ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n') {
                if (ch == '\n') {
                    self.line += 1;
                    self.col = 1;
                }
                pos.* += 1;
                continue;
            }
            if (ch == '/' and pos.* + 1 < self.source.len and self.source[pos.* + 1] == '/') {
                while (pos.* < self.source.len and self.source[pos.*] != '\n') : (pos.* += 1) {}
                if (pos.* < self.source.len and self.source[pos.*] == '\n') {
                    pos.* += 1;
                    self.line += 1;
                    self.col = 1;
                }
                continue;
            }
            break;
        }
    }

    fn skipInlineSpace(self: *Parser, pos: *usize) void {
        while (pos.* < self.source.len and (self.source[pos.*] == ' ' or self.source[pos.*] == '\t')) : (pos.* += 1) {}
    }

    fn peekString(self: *Parser, pos: *const usize, expected: []const u8) bool {
        if (pos.* + expected.len > self.source.len) return false;
        return std.mem.eql(u8, self.source[pos.* .. pos.* + expected.len], expected);
    }

    fn expectString(self: *Parser, pos: *usize, expected: []const u8) ParseError!void {
        if (!self.peekString(pos, expected)) return ParseError.UnexpectedToken;
        pos.* += expected.len;
    }

    fn expectChar(self: *Parser, pos: *usize, expected: u8) ParseError!void {
        if (pos.* >= self.source.len or self.source[pos.*] != expected) return ParseError.UnexpectedToken;
        pos.* += 1;
    }

    fn parseQuotedIdent(self: *Parser, allocator: std.mem.Allocator, pos: *usize) ParseError![]const u8 {
        if (pos.* >= self.source.len or self.source[pos.*] != '"') return ParseError.UnexpectedToken;
        pos.* += 1;
        const start = pos.*;
        while (pos.* < self.source.len and self.source[pos.*] != '"') : (pos.* += 1) {}
        if (pos.* >= self.source.len) return ParseError.UnexpectedEOF;
        const ident = self.source[start..pos.*];
        pos.* += 1;
        if (ident.len == 0) return ParseError.InvalidComponentName;
        if (!isIdentStart(ident[0])) return ParseError.InvalidComponentName;
        for (ident[1..]) |c| {
            if (!isIdentChar(c)) return ParseError.InvalidComponentName;
        }
        return try allocator.dupe(u8, ident);
    }

    fn skipChunkWhitespace(self: *Parser, chunk: []const u8, pos: *usize) void {
        _ = self;
        while (pos.* < chunk.len) {
            const ch = chunk[pos.*];
            if (ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n') {
                pos.* += 1;
                continue;
            }
            break;
        }
    }

    fn skipChunkInlineSpace(self: *Parser, chunk: []const u8, pos: *usize) void {
        _ = self;
        while (pos.* < chunk.len and (chunk[pos.*] == ' ' or chunk[pos.*] == '\t' or chunk[pos.*] == '\r')) : (pos.* += 1) {}
    }

    fn expectChunkChar(self: *Parser, chunk: []const u8, pos: *usize, expected: u8) ParseError!void {
        _ = self;
        if (pos.* >= chunk.len or chunk[pos.*] != expected) return ParseError.UnexpectedToken;
        pos.* += 1;
    }

    fn parseChunkIdent(self: *Parser, allocator: std.mem.Allocator, chunk: []const u8, pos: *usize) ParseError![]const u8 {
        _ = self;
        if (pos.* >= chunk.len or !isIdentStart(chunk[pos.*])) return ParseError.UnexpectedToken;
        const start = pos.*;
        pos.* += 1;
        while (pos.* < chunk.len and (isIdentChar(chunk[pos.*]) or chunk[pos.*] == '-' or chunk[pos.*] == '.')) : (pos.* += 1) {}
        return try allocator.dupe(u8, chunk[start..pos.*]);
    }
};

pub const SaxParser = Parser;

test "parser accepts a simple component" {
    const source =
        \\<Component name="Counter">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\
        \\  <div class="counter">
        \\    <h1>{count}</h1>
        \\    <button onclick={^inc}>+1</button>
        \\  </div>
        \\
        \\  @inc:
        \\  L_ENTRY:
        \\    count = load state+Counter_count as i64
        \\    call @render()
        \\    ret
        \\
        \\  !count
        \\</Component>
    ;
    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 1), program.components.len);
    try std.testing.expectEqualStrings("Counter", program.components[0].name);
    try std.testing.expectEqual(@as(usize, 1), program.components[0].state_vars.len);
    try std.testing.expectEqual(@as(usize, 1), program.components[0].handlers.len);
    try std.testing.expectEqual(@as(usize, 3), program.components[0].dom_nodes.len);
    try std.testing.expectEqual(@as(usize, 1), program.components[0].root_nodes.len);
    try std.testing.expectEqual(@as(usize, 0), program.components[0].root_nodes[0]);
}

test "parser accepts the counter example from the docs" {
    const source =
        \\<Component name="Counter">
        \\  <state>
        \\    count = 0
        \\    last = 0
        \\  </state>
        \\
        \\  <div class="counter">
        \\    <h1>{count}</h1>
        \\    <p>Last updated: {last} ms ago</p>
        \\    <button onclick={^inc}>+1</button>
        \\    <button onclick={^dec}>-1</button>
        \\    <button onclick={^reset}>Reset</button>
        \\  </div>
        \\
        \\  @inc:
        \\  L_ENTRY:
        \\    count = load state+Counter_count as i64
        \\    count = add count, 1
        \\    store state+Counter_count, count as i64
        \\    last = call @sax_get_time()
        \\    store state+Counter_last, last as i64
        \\    call @render()
        \\    ret
        \\
        \\  @dec:
        \\  L_ENTRY:
        \\    count = load state+Counter_count as i64
        \\    count = sub count, 1
        \\    store state+Counter_count, count as i64
        \\    last = call @sax_get_time()
        \\    store state+Counter_last, last as i64
        \\    call @render()
        \\    ret
        \\
        \\  @reset:
        \\  L_ENTRY:
        \\    store state+Counter_count, 0 as i64
        \\    last = call @sax_get_time()
        \\    store state+Counter_last, last as i64
        \\    call @render()
        \\    ret
        \\
        \\  !count !last
        \\</Component>
    ;
    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 1), program.components.len);
    const component = program.components[0];
    try std.testing.expectEqualStrings("Counter", component.name);
    try std.testing.expectEqual(@as(usize, 2), component.state_vars.len);
    try std.testing.expectEqual(@as(usize, 3), component.handlers.len);
    try std.testing.expectEqual(@as(usize, 2), component.release_vars.len);
    try std.testing.expectEqual(@as(usize, 6), component.dom_nodes.len);
    try std.testing.expectEqual(@as(usize, 1), component.root_nodes.len);
    try std.testing.expectEqual(@as(usize, 0), component.root_nodes[0]);
}

test "parser records interpolation dependencies" {
    const source =
        \\<Component name="Deps">
        \\  <state>
        \\    count = 0
        \\    label = 0
        \\  </state>
        \\  <div><p>{count + label}</p></div>
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const node = program.components[0].dom_nodes[0];
    try std.testing.expectEqual(@as(usize, 1), node.children.len);
    const child_node_idx = node.children[0].node_index;
    const child_node = program.components[0].dom_nodes[child_node_idx];
    try std.testing.expectEqual(@as(usize, 1), child_node.children.len);
    const text_piece = child_node.children[0].text;
    switch (text_piece) {
        .text => return error.TestUnexpectedResult,
        .interpolation => |expr| {
            try std.testing.expectEqualStrings("count + label", expr.expr);
            try std.testing.expectEqual(@as(usize, 2), expr.deps.len);
            try std.testing.expectEqualStrings("count", expr.deps[0]);
            try std.testing.expectEqualStrings("label", expr.deps[1]);
        },
        .json_string_interpolation => return error.TestUnexpectedResult,
        .json_object_spread => return error.TestUnexpectedResult,
    }
}

test "parser preserves literal spacing around interpolation pieces" {
    const source =
        \\<Component name="Spacing">
        \\  <state>
        \\    score = 7
        \\    latency = 180
        \\  </state>
        \\  <section>
        \\    <p>Score: {score}</p>
        \\    <p>{latency} ms</p>
        \\  </section>
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const component = program.components[0];
    try std.testing.expectEqual(@as(usize, 3), component.dom_nodes.len);

    const score_p = component.dom_nodes[1];
    try std.testing.expectEqual(@as(usize, 2), score_p.children.len);
    switch (score_p.children[0].text) {
        .text => |text| try std.testing.expectEqualStrings("Score: ", text),
        .interpolation => return error.TestUnexpectedResult,
        .json_string_interpolation => return error.TestUnexpectedResult,
        .json_object_spread => return error.TestUnexpectedResult,
    }
    switch (score_p.children[1].text) {
        .text => return error.TestUnexpectedResult,
        .interpolation => |expr| try std.testing.expectEqualStrings("score", expr.expr),
        .json_string_interpolation => return error.TestUnexpectedResult,
        .json_object_spread => return error.TestUnexpectedResult,
    }

    const latency_p = component.dom_nodes[2];
    try std.testing.expectEqual(@as(usize, 2), latency_p.children.len);
    switch (latency_p.children[0].text) {
        .text => return error.TestUnexpectedResult,
        .interpolation => |expr| try std.testing.expectEqualStrings("latency", expr.expr),
        .json_string_interpolation => return error.TestUnexpectedResult,
        .json_object_spread => return error.TestUnexpectedResult,
    }
    switch (latency_p.children[1].text) {
        .text => |text| try std.testing.expectEqualStrings(" ms", text),
        .interpolation => return error.TestUnexpectedResult,
        .json_string_interpolation => return error.TestUnexpectedResult,
        .json_object_spread => return error.TestUnexpectedResult,
    }
}

test "parser accepts whitelisted DOM attrs and route attrs" {
    const source =
        \\<Component name="HomePage">
        \\  <input class="field" style="width: 100%" value="{count}" defaultValue="0" placeholder="Count" disabled="disabled" defaultChecked />
        \\  <canvas id="wgpu-canvas" width="800" height="600" renderer="wgpu"></canvas>
        \\</Component>
        \\<Component name="App">
        \\  <Router>
        \\    <Page path="/" component="HomePage" />
        \\  </Router>
        \\</Component>
    ;
    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 2), program.components.len);
    try std.testing.expectEqual(@as(usize, 7), program.components[0].dom_nodes[0].attrs.len);
    try std.testing.expectEqual(@as(usize, 4), program.components[0].dom_nodes[1].attrs.len);
    try std.testing.expectEqualStrings("value", program.components[0].dom_nodes[0].attrs[2].name);
    try std.testing.expectEqualStrings("defaultValue", program.components[0].dom_nodes[0].attrs[3].name);
    try std.testing.expectEqualStrings("defaultChecked", program.components[0].dom_nodes[0].attrs[6].name);
    try std.testing.expectEqual(@as(usize, 1), program.components[1].route_pages.len);
    try std.testing.expectEqualStrings("/", program.components[1].route_pages[0].path);
    try std.testing.expectEqualStrings("HomePage", program.components[1].route_pages[0].component);
}

test "parser accepts broad React DOM and SVG intrinsic coverage" {
    const source =
        \\<Component name="Surface">
        \\  <dialog open="open" aria-label="Settings" data-kind="modal" contentEditable="true" spellCheck="false" translate="no" itemScope itemType="https://schema.org/Thing" itemID="thing-1" itemRef="thing-ref" itemProp="mainEntity">
        \\    <details open="open"><summary>Advanced</summary><meter min="0" max="10" value="4"></meter></details>
        \\    <input type="range" min="0" max="100" step="5" value="50" tabIndex="0" inputMode="numeric" enterKeyHint="done" autoCapitalize="none" autoCorrect="off" onPointerDown={^drag} />
        \\    <img referrerPolicy="no-referrer" />
        \\    <video><track kind="captions" srcLang="en" /></video>
        \\    <table><tbody><tr><td rowSpan="2" colSpan="3">Cell</td></tr></tbody></table>
        \\    <time dateTime="2026-06-08">Today</time>
        \\    <meta charSet="utf-8" />
        \\    <svg viewBox="0 0 10 10" role="img"><rect x="1" y="1" width="8" height="8" fill="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" fillRule="evenodd" clipRule="evenodd" vectorEffect="non-scaling-stroke" xlinkHref="#shape"></rect></svg>
        \\  </dialog>
        \\  @drag:
        \\  L_ENTRY:
        \\    ret
        \\</Component>
    ;
    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const component = program.components[0];
    try std.testing.expectEqual(@as(usize, 16), component.dom_nodes.len);
    try std.testing.expectEqualStrings("dialog", component.dom_nodes[0].tag);
    try std.testing.expectEqualStrings("contenteditable", component.dom_nodes[0].attrs[3].name);
    try std.testing.expectEqualStrings("spellcheck", component.dom_nodes[0].attrs[4].name);
    try std.testing.expectEqualStrings("translate", component.dom_nodes[0].attrs[5].name);
    try std.testing.expectEqualStrings("itemscope", component.dom_nodes[0].attrs[6].name);
    try std.testing.expectEqualStrings("itemtype", component.dom_nodes[0].attrs[7].name);
    try std.testing.expectEqualStrings("itemid", component.dom_nodes[0].attrs[8].name);
    try std.testing.expectEqualStrings("itemref", component.dom_nodes[0].attrs[9].name);
    try std.testing.expectEqualStrings("itemprop", component.dom_nodes[0].attrs[10].name);
    try std.testing.expectEqualStrings("input", component.dom_nodes[4].tag);
    try std.testing.expectEqualStrings("tabindex", component.dom_nodes[4].attrs[5].name);
    try std.testing.expectEqualStrings("inputmode", component.dom_nodes[4].attrs[6].name);
    try std.testing.expectEqualStrings("enterkeyhint", component.dom_nodes[4].attrs[7].name);
    try std.testing.expectEqualStrings("autocapitalize", component.dom_nodes[4].attrs[8].name);
    try std.testing.expectEqualStrings("autocorrect", component.dom_nodes[4].attrs[9].name);
    try std.testing.expectEqualStrings("onpointerdown", component.dom_nodes[4].attrs[10].name);
    try std.testing.expectEqualStrings("img", component.dom_nodes[5].tag);
    try std.testing.expectEqualStrings("referrerpolicy", component.dom_nodes[5].attrs[0].name);
    try std.testing.expectEqualStrings("track", component.dom_nodes[7].tag);
    try std.testing.expectEqualStrings("kind", component.dom_nodes[7].attrs[0].name);
    try std.testing.expectEqualStrings("srclang", component.dom_nodes[7].attrs[1].name);
    try std.testing.expectEqualStrings("td", component.dom_nodes[11].tag);
    try std.testing.expectEqualStrings("rowspan", component.dom_nodes[11].attrs[0].name);
    try std.testing.expectEqualStrings("colspan", component.dom_nodes[11].attrs[1].name);
    try std.testing.expectEqualStrings("datetime", component.dom_nodes[12].attrs[0].name);
    try std.testing.expectEqualStrings("charset", component.dom_nodes[13].attrs[0].name);
    try std.testing.expectEqualStrings("svg", component.dom_nodes[14].tag);
    try std.testing.expectEqualStrings("rect", component.dom_nodes[15].tag);
    try std.testing.expectEqualStrings("viewBox", component.dom_nodes[14].attrs[0].name);
    try std.testing.expectEqualStrings("stroke-width", component.dom_nodes[15].attrs[5].name);
    try std.testing.expectEqualStrings("stroke-linecap", component.dom_nodes[15].attrs[6].name);
    try std.testing.expectEqualStrings("stroke-linejoin", component.dom_nodes[15].attrs[7].name);
    try std.testing.expectEqualStrings("fill-rule", component.dom_nodes[15].attrs[8].name);
    try std.testing.expectEqualStrings("clip-rule", component.dom_nodes[15].attrs[9].name);
    try std.testing.expectEqualStrings("vector-effect", component.dom_nodes[15].attrs[10].name);
    try std.testing.expectEqualStrings("xlink:href", component.dom_nodes[15].attrs[11].name);
}

test "parser accepts user components with props and children" {
    const source =
        \\<Component name="App">
        \\  <Layout title="Home" count="{count}">
        \\    <span className="label">Hi</span>
        \\  </Layout>
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 1), program.components.len);
    try std.testing.expectEqual(@as(usize, 2), program.components[0].dom_nodes.len);

    const layout = program.components[0].dom_nodes[0];
    try std.testing.expect(layout.is_user_component);
    try std.testing.expectEqualStrings("Layout", layout.tag);
    try std.testing.expectEqual(@as(usize, 2), layout.attrs.len);
    try std.testing.expectEqualStrings("title", layout.attrs[0].name);
    try std.testing.expectEqualStrings("count", layout.attrs[1].name);
    try std.testing.expectEqual(@as(usize, 1), layout.children.len);

    const child_idx = layout.children[0].node_index;
    const child = program.components[0].dom_nodes[child_idx];
    try std.testing.expect(!child.is_user_component);
    try std.testing.expectEqualStrings("span", child.tag);
    try std.testing.expectEqualStrings("class", child.attrs[0].name);
}

test "parser normalizes static user component object props" {
    const source =
        \\<Component name="App">
        \\  <Widget config={{ ["title"]: "Object Prop", ...{ spread: "static" }, count: 3, active: true, empty: null, tags: ["alpha", "beta"], nested: { ["size"]: 2, ...{ enabled: false } } }} />
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.is_user_component);
    try std.testing.expectEqualStrings("config", widget.attrs[0].name);
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .literal => |lit| try std.testing.expectEqualStrings("{\"title\":\"Object Prop\",\"spread\":\"static\",\"count\":3,\"active\":true,\"empty\":null,\"tags\":[\"alpha\",\"beta\"],\"nested\":{\"size\":2,\"enabled\":false}}", lit),
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves dynamic user component object props as templates" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 0
        \\    idle_score = 9
        \\    small_score = 3 as i32
        \\    fallback_small_score = 2 as i32
        \\    ratio = 0.75 as f64
        \\    fallback_ratio = 0.5 as f64
        \\    active = 0 as i1
        \\    fallback_active = 0 as i1
        \\    title = alloc 32
        \\    title_len = 0
        \\    fallback = alloc 32
        \\    fallback_len = 0
        \\    extra = alloc 64
        \\    extra_len = 0
        \\  </state>
        \\  <Widget config={{ ["title"]: title, ...{ spread: "static", spread_count: count }, count: count, active: active, status: active ? title : fallback, label: active ? "ready" : fallback, score: active ? count : idle_score, bonus: active ? count : 0, rating: active ? small_score : fallback_small_score, visible: active ? active : fallback_active, precision: active ? ratio : fallback_ratio, nested: { ["current"]: count, ...{ enabled: true, spread_active: active } }, ...extra }} />
        \\  !count !idle_score !small_score !fallback_small_score !ratio !fallback_ratio !active !fallback_active !title !title_len !fallback !fallback_len !extra !extra_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 29), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"title\":", txt),
                .interpolation => return error.TestUnexpectedResult,
                .json_string_interpolation => return error.TestUnexpectedResult,
                .json_object_spread => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("title", expr.expr),
                .text => return error.TestUnexpectedResult,
                .json_string_interpolation => return error.TestUnexpectedResult,
                .json_object_spread => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                .text => return error.TestUnexpectedResult,
                .json_string_interpolation => return error.TestUnexpectedResult,
                .json_object_spread => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                .text => return error.TestUnexpectedResult,
                .json_string_interpolation => return error.TestUnexpectedResult,
                .json_object_spread => return error.TestUnexpectedResult,
            }
            switch (pieces[7]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                .text => return error.TestUnexpectedResult,
                .json_string_interpolation => return error.TestUnexpectedResult,
                .json_object_spread => return error.TestUnexpectedResult,
            }
            switch (pieces[9]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? title : fallback", expr.expr),
                .text => return error.TestUnexpectedResult,
                .json_string_interpolation => return error.TestUnexpectedResult,
                .json_object_spread => return error.TestUnexpectedResult,
            }
            switch (pieces[11]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? \"ready\" : fallback", expr.expr),
                .text => return error.TestUnexpectedResult,
                .json_string_interpolation => return error.TestUnexpectedResult,
                .json_object_spread => return error.TestUnexpectedResult,
            }
            switch (pieces[13]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? count : idle_score", expr.expr),
                .text => return error.TestUnexpectedResult,
                .json_string_interpolation => return error.TestUnexpectedResult,
                .json_object_spread => return error.TestUnexpectedResult,
            }
            switch (pieces[15]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? count : 0", expr.expr),
                .text => return error.TestUnexpectedResult,
                .json_string_interpolation => return error.TestUnexpectedResult,
                .json_object_spread => return error.TestUnexpectedResult,
            }
            switch (pieces[17]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? small_score : fallback_small_score", expr.expr),
                .text => return error.TestUnexpectedResult,
                .json_string_interpolation => return error.TestUnexpectedResult,
                .json_object_spread => return error.TestUnexpectedResult,
            }
            switch (pieces[19]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? active : fallback_active", expr.expr),
                .text => return error.TestUnexpectedResult,
                .json_string_interpolation => return error.TestUnexpectedResult,
                .json_object_spread => return error.TestUnexpectedResult,
            }
            switch (pieces[21]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? ratio : fallback_ratio", expr.expr),
                .text => return error.TestUnexpectedResult,
                .json_string_interpolation => return error.TestUnexpectedResult,
                .json_object_spread => return error.TestUnexpectedResult,
            }
            switch (pieces[23]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                .text => return error.TestUnexpectedResult,
                .json_string_interpolation => return error.TestUnexpectedResult,
                .json_object_spread => return error.TestUnexpectedResult,
            }
            switch (pieces[25]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                .text => return error.TestUnexpectedResult,
                .json_string_interpolation => return error.TestUnexpectedResult,
                .json_object_spread => return error.TestUnexpectedResult,
            }
            switch (pieces[27]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("extra", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[28]) {
                .text => |txt| try std.testing.expectEqualStrings("}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves dynamic computed keys inside static spread literals" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ ...{ [active ? "spread_ready" : "spread_idle"]: count, [count + 100]: active, spread_count: count }, count: count }} />
        \\  !count !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 13), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? \"spread_ready\" : \"spread_idle\"", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("count + 100", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[7]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[8]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"spread_count\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[9]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[10]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"count\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[11]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[12]) {
                .text => |txt| try std.testing.expectEqualStrings("}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves scalar computed keys inside static spread literals" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ ...{ [count + 100]: active }, count: count }} />
        \\  !count !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 7), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[4]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"count\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("count + 100", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[6]) {
                .text => |txt| try std.testing.expectEqualStrings("}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves boolean computed keys inside static spread literals" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ ...{ [active]: count, spread_count: count }, current: count }} />
        \\  !count !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 9), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[4]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"spread_count\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[6]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[7]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[8]) {
                .text => |txt| try std.testing.expectEqualStrings("}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves dynamic computed keys inside nested static spread literals" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ nested: { ...{ [active ? "nested_spread_ready" : "nested_spread_idle"]: count, [count + 200]: active, spread_active: active }, current: count } }} />
        \\  !count !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 13), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"nested\":{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? \"nested_spread_ready\" : \"nested_spread_idle\"", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("count + 200", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[7]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[8]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"spread_active\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[9]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[10]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[11]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[12]) {
                .text => |txt| try std.testing.expectEqualStrings("}}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves scalar computed keys inside array item static spread literals" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ items: [{ size: 1, ...{ [count + 200]: active, spread_active: active }, current: count }] }} />
        \\  !count !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 9), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"items\":[{\"size\":1,", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("count + 200", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[4]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"spread_active\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[6]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[7]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[8]) {
                .text => |txt| try std.testing.expectEqualStrings("}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves boolean computed keys inside array item static spread literals" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ items: [{ size: 1, ...{ [active]: count, spread_active: active }, current: count }] }} />
        \\  !count !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 9), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"items\":[{\"size\":1,", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[4]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"spread_active\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[6]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[7]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[8]) {
                .text => |txt| try std.testing.expectEqualStrings("}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves i1 ternary computed keys inside array item static spread literals" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    idle_score = 9
        \\    active = 0 as i1
        \\    fallback_active = 0 as i1
        \\  </state>
        \\  <Widget config={{ ternary_static_spread_items: [{ ...{ [active ? active : fallback_active]: idle_score, current: count } }] }} />
        \\  !count !idle_score !active !fallback_active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 7), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"ternary_static_spread_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? active : fallback_active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("idle_score", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[4]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[6]) {
                .text => |txt| try std.testing.expectEqualStrings("}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves i1 literal branch computed keys inside array item static spread literals" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    active = 0 as i1
        \\    fallback_active = 0 as i1
        \\  </state>
        \\  <Widget config={{ ternary_static_spread_items: [{ ...{ [active ? fallback_active : true]: count, current: count } }] }} />
        \\  !count !active !fallback_active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 7), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"ternary_static_spread_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? fallback_active : true", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[4]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[6]) {
                .text => |txt| try std.testing.expectEqualStrings("}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves i1 literal-only branch computed keys inside array item static spread literals" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ ternary_static_spread_items: [{ ...{ [active ? false : true]: count, current: count } }] }} />
        \\  !count !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 7), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"ternary_static_spread_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? false : true", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[4]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[6]) {
                .text => |txt| try std.testing.expectEqualStrings("}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves scalar computed keys inside leading nested static spread literals" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ leading_static_spread_nested: { ...{ [active ? "leading_nested_spread_ready" : "leading_nested_spread_idle"]: count, [count + 400]: active, spread_active: active }, current: count } }} />
        \\  !count !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 13), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"leading_static_spread_nested\":{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? \"leading_nested_spread_ready\" : \"leading_nested_spread_idle\"", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("count + 400", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[7]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[8]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"spread_active\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[9]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[10]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[11]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[12]) {
                .text => |txt| try std.testing.expectEqualStrings("}}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves dynamic computed keys inside leading array item static spread literals" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ leading_static_spread_items: [{ ...{ [active ? "leading_spread_ready" : "leading_spread_idle"]: count, [count + 300]: active, enabled: true, spread_active: active }, current: count }] }} />
        \\  !count !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 13), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"leading_static_spread_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? \"leading_spread_ready\" : \"leading_spread_idle\"", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("count + 300", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[7]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[8]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"enabled\":true,\"spread_active\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[9]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[10]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[11]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[12]) {
                .text => |txt| try std.testing.expectEqualStrings("}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves dynamic computed user component object keys" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    idle_score = 9
        \\    small_score = 3 as i32
        \\    fallback_small_score = 2 as i32
        \\    ratio = 0.75 as f64
        \\    fallback_ratio = 0.5 as f64
        \\    active = 0 as i1
        \\    fallback_active = 0 as i1
        \\    title = alloc 32
        \\    title_len = 0
        \\    fallback = alloc 32
        \\    fallback_len = 0
        \\  </state>
        \\  <Widget config={{ [title]: "dynamic", [count + 1]: count, [((count + 2) * 3) - 1]: active, [active ? "enabled" : "disabled"]: count, [active ? title : fallback]: count, [active ? "ready" : fallback]: count, [active ? count : idle_score]: active, [active ? active : fallback_active]: count, [active ? small_score : fallback_small_score]: active, [active ? ratio : fallback_ratio]: count, [active]: active }} />
        \\  !count !idle_score !small_score !fallback_small_score !ratio !fallback_ratio !active !fallback_active !title !title_len !fallback !fallback_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 43), pieces.len);
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("title", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("count + 1", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[7]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("((count + 2) * 3) - 1", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[9]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[11]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? \"enabled\" : \"disabled\"", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[13]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[15]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? title : fallback", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[17]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[19]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? \"ready\" : fallback", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[21]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[23]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? count : idle_score", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[25]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[27]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? active : fallback_active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[29]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[31]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? small_score : fallback_small_score", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[33]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[35]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? ratio : fallback_ratio", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[37]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[39]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[40]) {
                .text => |txt| try std.testing.expectEqualStrings(":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[41]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[42]) {
                .text => |txt| try std.testing.expectEqualStrings("}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves nested dynamic computed user component object keys" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    idle_score = 9
        \\    active = 0 as i1
        \\    title = alloc 32
        \\    title_len = 0
        \\    fallback = alloc 32
        \\    fallback_len = 0
        \\  </state>
        \\  <Widget config={{ nested: { size: 2, [active ? "nested_ready" : "nested_idle"]: count, [active ? count : idle_score]: active, [active ? title : fallback]: count, current: count } }} />
        \\  !count !idle_score !active !title !title_len !fallback !fallback_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 15), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"nested\":{\"size\":2,", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? \"nested_ready\" : \"nested_idle\"", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? count : idle_score", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[7]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[9]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? title : fallback", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[11]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[12]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[13]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[14]) {
                .text => |txt| try std.testing.expectEqualStrings("}}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves leading nested dynamic computed user component object keys" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    idle_score = 9
        \\    active = 0 as i1
        \\    title = alloc 32
        \\    title_len = 0
        \\    fallback = alloc 32
        \\    fallback_len = 0
        \\  </state>
        \\  <Widget config={{ leading_nested: { [active ? "leading_nested_ready" : "leading_nested_idle"]: count, [active ? count : idle_score]: active, [active ? title : fallback]: count, current: count } }} />
        \\  !count !idle_score !active !title !title_len !fallback !fallback_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 15), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"leading_nested\":{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? \"leading_nested_ready\" : \"leading_nested_idle\"", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? count : idle_score", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[7]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[9]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? title : fallback", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[11]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[12]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[13]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[14]) {
                .text => |txt| try std.testing.expectEqualStrings("}}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves i64 literal branch computed object keys" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ [active ? count : 0]: count }} />
        \\  !count !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 5), pieces.len);
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? count : 0", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves f64 literal branch object and array values" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    ratio = 0.75 as f64
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ precision_floor: active ? ratio : 0.25, variants: [active ? ratio : 0.25] }} />
        \\  !ratio !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 5), pieces.len);
            switch (pieces[1]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? ratio : 0.25", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? ratio : 0.25", expr.expr),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves f64 literal branch computed object keys" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    ratio = 0.75 as f64
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ [active ? ratio : 0.25]: count }} />
        \\  !count !ratio !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 5), pieces.len);
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? ratio : 0.25", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves i32 literal branch object and array values" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    small_score = 3 as i32
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ rating_floor: active ? small_score : 4, variants: [active ? small_score : 4] }} />
        \\  !small_score !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 5), pieces.len);
            switch (pieces[1]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? small_score : 4", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? small_score : 4", expr.expr),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves i32 literal branch computed object keys" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    small_score = 3 as i32
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ [active ? small_score : 4]: active }} />
        \\  !small_score !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 5), pieces.len);
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? small_score : 4", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves i1 literal branch object and array values" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    fallback_active = 0 as i1
        \\  </state>
        \\  <Widget config={{ pinned: active ? true : fallback_active, variants: [active ? false : true] }} />
        \\  !active !fallback_active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 5), pieces.len);
            switch (pieces[1]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? true : fallback_active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? false : true", expr.expr),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves i1 literal branch computed object keys" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    active = 0 as i1
        \\    fallback_active = 0 as i1
        \\  </state>
        \\  <Widget config={{ [active ? fallback_active : true]: count }} />
        \\  !count !active !fallback_active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 5), pieces.len);
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? fallback_active : true", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves null literal branch string object and array values" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    title = alloc 32
        \\    title_len = 0
        \\    fallback = alloc 32
        \\    fallback_len = 0
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ nullable: active ? title : null, variants: [active ? null : fallback] }} />
        \\  !title !title_len !fallback !fallback_len !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 5), pieces.len);
            switch (pieces[1]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? title : null", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? null : fallback", expr.expr),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves null literal branch computed object keys" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    status_fallback = alloc 32
        \\    status_fallback_len = 0
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ [active ? status_fallback : null]: count }} />
        \\  !count !status_fallback !status_fallback_len !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 5), pieces.len);
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? status_fallback : null", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves dynamic array values in user component object props" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    idle_score = 9
        \\    small_score = 3 as i32
        \\    fallback_small_score = 2 as i32
        \\    ratio = 0.75 as f64
        \\    fallback_ratio = 0.5 as f64
        \\    active = 0 as i1
        \\    fallback_active = 0 as i1
        \\    title = alloc 32
        \\    title_len = 0
        \\    fallback = alloc 32
        \\    fallback_len = 0
        \\  </state>
        \\  <Widget config={{ tags: ["alpha", title, count, active, active ? title : fallback, active ? count : idle_score, active ? count : 0, active ? small_score : fallback_small_score, active ? active : fallback_active, active ? ratio : fallback_ratio, active ? "ready" : fallback] }} />
        \\  !count !idle_score !small_score !fallback_small_score !ratio !fallback_ratio !active !fallback_active !title !title_len !fallback !fallback_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 21), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"tags\":[\"alpha\",", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("title", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[6]) {
                .text => |txt| try std.testing.expectEqualStrings(",", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[7]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? title : fallback", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[9]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? count : idle_score", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[11]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? count : 0", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[13]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? small_score : fallback_small_score", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[14]) {
                .text => |txt| try std.testing.expectEqualStrings(",", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[15]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? active : fallback_active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[16]) {
                .text => |txt| try std.testing.expectEqualStrings(",", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[17]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? ratio : fallback_ratio", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[18]) {
                .text => |txt| try std.testing.expectEqualStrings(",", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[19]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active ? \"ready\" : fallback", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[20]) {
                .text => |txt| try std.testing.expectEqualStrings("]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves non-trailing dynamic user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    config = alloc 32
        \\    config_len = 0
        \\  </state>
        \\  <Widget config={{ before: 1, ...config, count: 2 }} />
        \\  !config !config_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"before\":1", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("config", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"count\":2}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves leading non-trailing dynamic user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    config = alloc 32
        \\    config_len = 0
        \\    fallback = alloc 32
        \\    fallback_len = 0
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ ...(active ? config : { fallback: true }), count: 1 }} />
        \\  !config !config_len !fallback !fallback_len !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active ? config : { fallback: true })", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"count\":1}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves ternary null branch user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ ...(active ? { active_null_branch: true } : null), count: 1 }} />
        \\  !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active ? { active_null_branch: true } : null)", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"count\":1}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves ptr ternary null branch user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ ...(active ? nested_extra : null), count: 1 }} />
        \\  !active !nested_extra !nested_extra_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active ? nested_extra : null)", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"count\":1}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves ptr ternary ptr branch user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\    object_branch = alloc 64
        \\    object_branch_len = 0
        \\  </state>
        \\  <Widget config={{ ...(active ? nested_extra : object_branch), count: 1 }} />
        \\  !active !nested_extra !nested_extra_len !object_branch !object_branch_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active ? nested_extra : object_branch)", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"count\":1}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves logical and user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ ...(active && { active_and_branch: true }), count: 1 }} />
        \\  !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active && { active_and_branch: true })", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"count\":1}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves negated logical and user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ ...(!active && { idle_and_branch: true }), count: 1 }} />
        \\  !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(!active && { idle_and_branch: true })", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"count\":1}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves logical and ptr user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    object_branch = alloc 64
        \\    object_branch_len = 0
        \\  </state>
        \\  <Widget config={{ ...(active && object_branch), count: 1 }} />
        \\  !active !object_branch !object_branch_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active && object_branch)", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"count\":1}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves negated logical and ptr user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    object_branch = alloc 64
        \\    object_branch_len = 0
        \\  </state>
        \\  <Widget config={{ ...(!active && object_branch), count: 1 }} />
        \\  !active !object_branch !object_branch_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(!active && object_branch)", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"count\":1}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves logical or user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ ...(active || { idle_or_branch: true }), count: 1 }} />
        \\  !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active || { idle_or_branch: true })", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"count\":1}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves negated logical or user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ ...(!active || { active_or_branch: true }), count: 1 }} />
        \\  !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(!active || { active_or_branch: true })", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"count\":1}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves logical or ptr user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ ...(active || nested_extra), count: 1 }} />
        \\  !active !nested_extra !nested_extra_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active || nested_extra)", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"count\":1}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves negated logical or ptr user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ ...(!active || nested_extra), count: 1 }} />
        \\  !active !nested_extra !nested_extra_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(!active || nested_extra)", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"count\":1}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves nested dynamic user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    nested_extra = alloc 32
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ nested: { size: 2, ...nested_extra, current: 1 } }} />
        \\  !nested_extra !nested_extra_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"nested\":{\"size\":2", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("nested_extra", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves nested ptr ternary null branch user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ nested: { size: 2, ...(active ? nested_extra : null), current: 1 } }} />
        \\  !active !nested_extra !nested_extra_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"nested\":{\"size\":2", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active ? nested_extra : null)", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves nested ptr ternary static branch user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ nested: { size: 2, ...(active ? nested_extra : { idle_nested_branch: true }), current: 1 } }} />
        \\  !active !nested_extra !nested_extra_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"nested\":{\"size\":2", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active ? nested_extra : { idle_nested_branch: true })", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves nested ptr ternary ptr branch user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\    object_branch = alloc 64
        \\    object_branch_len = 0
        \\  </state>
        \\  <Widget config={{ nested: { size: 2, ...(active ? nested_extra : object_branch), current: 1 } }} />
        \\  !active !nested_extra !nested_extra_len !object_branch !object_branch_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"nested\":{\"size\":2", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active ? nested_extra : object_branch)", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves nested ternary null branch object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ nested: { size: 2, ...(active ? { active_nested_branch: true } : null), current: 1 } }} />
        \\  !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"nested\":{\"size\":2", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active ? { active_nested_branch: true } : null)", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves nested logical and object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ nested: { size: 2, ...(active && { active_nested_and: true }), ...(!active && { idle_nested_and: true }), current: 1 } }} />
        \\  !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 4), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"nested\":{\"size\":2", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active && { active_nested_and: true })", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(!active && { idle_nested_and: true })", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves nested logical or object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ nested: { size: 2, ...(active || { idle_nested_or: true }), ...(!active || { active_nested_or: true }), current: 1 } }} />
        \\  !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 4), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"nested\":{\"size\":2", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active || { idle_nested_or: true })", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(!active || { active_nested_or: true })", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves nested logical and ptr user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    object_branch = alloc 64
        \\    object_branch_len = 0
        \\  </state>
        \\  <Widget config={{ nested: { size: 2, ...(active && object_branch), current: 1 } }} />
        \\  !active !object_branch !object_branch_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"nested\":{\"size\":2", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active && object_branch)", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves nested negated logical and ptr user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    object_branch = alloc 64
        \\    object_branch_len = 0
        \\  </state>
        \\  <Widget config={{ nested: { size: 2, ...(!active && object_branch), current: 1 } }} />
        \\  !active !object_branch !object_branch_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"nested\":{\"size\":2", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(!active && object_branch)", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves nested logical or ptr user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    object_branch = alloc 64
        \\    object_branch_len = 0
        \\  </state>
        \\  <Widget config={{ nested: { size: 2, ...(active || object_branch), current: 1 } }} />
        \\  !active !object_branch !object_branch_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"nested\":{\"size\":2", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active || object_branch)", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves nested negated logical or ptr user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    object_branch = alloc 64
        \\    object_branch_len = 0
        \\  </state>
        \\  <Widget config={{ nested: { size: 2, ...(!active || object_branch), current: 1 } }} />
        \\  !active !object_branch !object_branch_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"nested\":{\"size\":2", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(!active || object_branch)", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves array item dynamic user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    nested_extra = alloc 32
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ items: [{ size: 1, ...nested_extra, current: 1 }] }} />
        \\  !nested_extra !nested_extra_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"items\":[{\"size\":1", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("nested_extra", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves array item dynamic computed user component object keys" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    idle_score = 9
        \\    active = 0 as i1
        \\    title = alloc 32
        \\    title_len = 0
        \\    fallback = alloc 32
        \\    fallback_len = 0
        \\  </state>
        \\  <Widget config={{ computed_items: [{ size: 1, [active ? "item_ready" : "item_idle"]: count, [active ? count : idle_score]: active, [active ? title : fallback]: count, current: count }] }} />
        \\  !count !idle_score !active !title !title_len !fallback !fallback_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 15), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"computed_items\":[{\"size\":1,", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? \"item_ready\" : \"item_idle\"", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? count : idle_score", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[7]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[9]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? title : fallback", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[11]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[12]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[13]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[14]) {
                .text => |txt| try std.testing.expectEqualStrings("}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves leading array item dynamic computed user component object keys" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 1
        \\    idle_score = 9
        \\    active = 0 as i1
        \\    title = alloc 32
        \\    title_len = 0
        \\    fallback = alloc 32
        \\    fallback_len = 0
        \\  </state>
        \\  <Widget config={{ leading_computed_items: [{ [active ? "leading_item_ready" : "leading_item_idle"]: count, [active ? count : idle_score]: active, [active ? title : fallback]: count, current: count }] }} />
        \\  !count !idle_score !active !title !title_len !fallback !fallback_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 15), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"leading_computed_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? \"leading_item_ready\" : \"leading_item_idle\"", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[3]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[5]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? count : idle_score", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[7]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("active", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[9]) {
                .json_string_interpolation => |expr| try std.testing.expectEqualStrings("active ? title : fallback", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[11]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[12]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[13]) {
                .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[14]) {
                .text => |txt| try std.testing.expectEqualStrings("}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves leading array item dynamic user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    nested_extra = alloc 32
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ leading_items: [{ ...nested_extra, current: 1 }] }} />
        \\  !nested_extra !nested_extra_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"leading_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("nested_extra", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves leading array item conditional user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ leading_conditional_items: [{ ...(!active && { idle_leading_item: true }), current: 1 }] }} />
        \\  !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"leading_conditional_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(!active && { idle_leading_item: true })", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves leading array item positive logical and user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ leading_active_items: [{ ...(active && { active_leading_item: true }), current: 1 }] }} />
        \\  !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"leading_active_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active && { active_leading_item: true })", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves leading array item positive logical and ptr user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ leading_ptr_and_items: [{ ...(active && nested_extra), current: 1 }] }} />
        \\  !active !nested_extra !nested_extra_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"leading_ptr_and_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active && nested_extra)", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves leading array item negated logical and ptr user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ leading_negated_ptr_and_items: [{ ...(!active && nested_extra), current: 1 }] }} />
        \\  !active !nested_extra !nested_extra_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"leading_negated_ptr_and_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(!active && nested_extra)", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves leading array item ternary null branch object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ leading_null_items: [{ ...(active ? { active_leading_branch: true } : null), current: 1 }] }} />
        \\  !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"leading_null_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active ? { active_leading_branch: true } : null)", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves leading array item ptr ternary null branch object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ leading_ptr_null_items: [{ ...(active ? nested_extra : null), current: 1 }] }} />
        \\  !active !nested_extra !nested_extra_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"leading_ptr_null_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active ? nested_extra : null)", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves leading array item ptr ternary static branch object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ leading_ptr_fallback_items: [{ ...(active ? nested_extra : { idle_ptr_fallback: true }), current: 1 }] }} />
        \\  !active !nested_extra !nested_extra_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"leading_ptr_fallback_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active ? nested_extra : { idle_ptr_fallback: true })", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves leading array item ptr ternary ptr branch object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\    object_branch = alloc 64
        \\    object_branch_len = 0
        \\  </state>
        \\  <Widget config={{ leading_ptr_branch_items: [{ ...(active ? nested_extra : object_branch), current: 1 }] }} />
        \\  !active !nested_extra !nested_extra_len !object_branch !object_branch_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"leading_ptr_branch_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active ? nested_extra : object_branch)", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves leading array item logical or user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ leading_or_items: [{ ...(active || { idle_leading_or: true }), current: 1 }] }} />
        \\  !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"leading_or_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active || { idle_leading_or: true })", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves leading array item logical or ptr user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ leading_ptr_or_items: [{ ...(active || nested_extra), current: 1 }] }} />
        \\  !active !nested_extra !nested_extra_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"leading_ptr_or_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active || nested_extra)", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves leading array item negated logical or user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ leading_negated_or_items: [{ ...(!active || { active_leading_or: true }), current: 1 }] }} />
        \\  !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"leading_negated_or_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(!active || { active_leading_or: true })", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves leading array item negated logical or ptr user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ leading_negated_ptr_or_items: [{ ...(!active || nested_extra), current: 1 }] }} />
        \\  !active !nested_extra !nested_extra_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"leading_negated_ptr_or_items\":[{", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(!active || nested_extra)", spread.expr.expr);
                    try std.testing.expect(!spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves array item conditional user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ items: [{ size: 1, ...(!active && { idle_item: true }), current: 1 }] }} />
        \\  !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"items\":[{\"size\":1", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(!active && { idle_item: true })", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves array item ternary null branch object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ items: [{ size: 1, ...(active ? { active_item_branch: true } : null), current: 1 }] }} />
        \\  !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"items\":[{\"size\":1", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active ? { active_item_branch: true } : null)", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves array item logical or user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ items: [{ size: 1, ...(active || { idle_item_or: true }), current: 1 }] }} />
        \\  !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"items\":[{\"size\":1", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active || { idle_item_or: true })", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves array item negated logical or user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ items: [{ size: 1, ...(!active || { active_item_or: true }), current: 1 }] }} />
        \\  !active
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"items\":[{\"size\":1", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(!active || { active_item_or: true })", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves array item logical or ptr user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    object_branch = alloc 64
        \\    object_branch_len = 0
        \\  </state>
        \\  <Widget config={{ items: [{ size: 1, ...(active || object_branch), current: 1 }] }} />
        \\  !active !object_branch !object_branch_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"items\":[{\"size\":1", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active || object_branch)", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves array item negated logical or ptr user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    object_branch = alloc 64
        \\    object_branch_len = 0
        \\  </state>
        \\  <Widget config={{ items: [{ size: 1, ...(!active || object_branch), current: 1 }] }} />
        \\  !active !object_branch !object_branch_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"items\":[{\"size\":1", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(!active || object_branch)", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves array item logical and ptr user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    object_branch = alloc 64
        \\    object_branch_len = 0
        \\  </state>
        \\  <Widget config={{ and_ptr_items: [{ size: 1, ...(active && object_branch), current: 1 }] }} />
        \\  !active !object_branch !object_branch_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"and_ptr_items\":[{\"size\":1", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(active && object_branch)", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves array item negated logical and ptr user component object spreads" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    object_branch = alloc 64
        \\    object_branch_len = 0
        \\  </state>
        \\  <Widget config={{ and_ptr_items: [{ size: 1, ...(!active && object_branch), current: 1 }] }} />
        \\  !active !object_branch !object_branch_len
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const widget = program.components[0].dom_nodes[0];
    try std.testing.expect(widget.attrs[0].is_object_prop);
    switch (widget.attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 3), pieces.len);
            switch (pieces[0]) {
                .text => |txt| try std.testing.expectEqualStrings("{\"and_ptr_items\":[{\"size\":1", txt),
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .json_object_spread => |spread| {
                    try std.testing.expectEqualStrings("(!active && object_branch)", spread.expr.expr);
                    try std.testing.expect(spread.prefix_comma);
                },
                else => return error.TestUnexpectedResult,
            }
            switch (pieces[2]) {
                .text => |txt| try std.testing.expectEqualStrings(",\"current\":1}]}", txt),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser records quoted attribute templates" {
    const source =
        \\<Component name="Templated">
        \\  <state>
        \\    label = alloc 32
        \\  </state>
        \\  <img alt="Label: {label}" />
        \\  <Badge title="Badge {label}" />
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const component = program.components[0];
    try std.testing.expectEqual(@as(usize, 2), component.dom_nodes.len);

    switch (component.dom_nodes[0].attrs[0].value) {
        .template => |pieces| {
            try std.testing.expectEqual(@as(usize, 2), pieces.len);
            switch (pieces[0]) {
                .text => |text| try std.testing.expectEqualStrings("Label: ", text),
                .interpolation => return error.TestUnexpectedResult,
                .json_string_interpolation => return error.TestUnexpectedResult,
                .json_object_spread => return error.TestUnexpectedResult,
            }
            switch (pieces[1]) {
                .text => return error.TestUnexpectedResult,
                .interpolation => |expr| try std.testing.expectEqualStrings("label", expr.expr),
                .json_string_interpolation => return error.TestUnexpectedResult,
                .json_object_spread => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }

    switch (component.dom_nodes[1].attrs[0].value) {
        .template => |pieces| try std.testing.expectEqual(@as(usize, 2), pieces.len),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(!component.dom_nodes[1].attrs[0].is_object_prop);
}

test "parser accepts braced non-event attrs and boolean shorthand props" {
    const source =
        \\<Component name="Props">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\  <input value={count} disabled />
        \\  <option defaultSelected>Advanced</option>
        \\  <select multiple></select>
        \\  <Badge count={count} active />
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const component = program.components[0];
    try std.testing.expectEqual(@as(usize, 4), component.dom_nodes.len);

    const input = component.dom_nodes[0];
    try std.testing.expectEqualStrings("value", input.attrs[0].name);
    switch (input.attrs[0].value) {
        .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("disabled", input.attrs[1].name);
    switch (input.attrs[1].value) {
        .literal => |lit| try std.testing.expectEqualStrings("1", lit),
        else => return error.TestUnexpectedResult,
    }

    const option = component.dom_nodes[1];
    try std.testing.expectEqualStrings("defaultSelected", option.attrs[0].name);
    switch (option.attrs[0].value) {
        .literal => |lit| try std.testing.expectEqualStrings("1", lit),
        else => return error.TestUnexpectedResult,
    }

    const select = component.dom_nodes[2];
    try std.testing.expectEqualStrings("multiple", select.attrs[0].name);
    switch (select.attrs[0].value) {
        .literal => |lit| try std.testing.expectEqualStrings("1", lit),
        else => return error.TestUnexpectedResult,
    }

    const badge = component.dom_nodes[3];
    try std.testing.expect(badge.is_user_component);
    switch (badge.attrs[0].value) {
        .interpolation => |expr| try std.testing.expectEqualStrings("count", expr.expr),
        else => return error.TestUnexpectedResult,
    }
    switch (badge.attrs[1].value) {
        .literal => |lit| try std.testing.expectEqualStrings("1", lit),
        else => return error.TestUnexpectedResult,
    }
}

test "parser accepts React-style event handler references" {
    const source =
        \\<Component name="Events">
        \\  <button onClick={inc}>+1</button>
        \\  @inc:
        \\  L_ENTRY:
        \\    ret
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const button = program.components[0].dom_nodes[0];
    try std.testing.expectEqual(@as(usize, 1), button.attrs.len);
    try std.testing.expect(button.attrs[0].is_event);
    try std.testing.expectEqualStrings("onclick", button.attrs[0].name);
    try std.testing.expectEqualStrings("inc", button.attrs[0].event_handler.?);
}

test "parser accepts React capture event handler references" {
    const source =
        \\<Component name="Events">
        \\  <button onClickCapture={capture}>+1</button>
        \\  @capture:
        \\  L_ENTRY:
        \\    ret
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const button = program.components[0].dom_nodes[0];
    try std.testing.expectEqual(@as(usize, 1), button.attrs.len);
    try std.testing.expect(button.attrs[0].is_event);
    try std.testing.expectEqualStrings("onclickcapture", button.attrs[0].name);
    try std.testing.expectEqualStrings("capture", button.attrs[0].event_handler.?);
}

test "parser accepts React mouse enter and leave event aliases" {
    const source =
        \\<Component name="Events">
        \\  <div onMouseEnter={enter} onMouseLeaveCapture={leave}></div>
        \\  @enter:
        \\  L_ENTRY:
        \\    ret
        \\  @leave:
        \\  L_ENTRY:
        \\    ret
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const div = program.components[0].dom_nodes[0];
    try std.testing.expectEqual(@as(usize, 2), div.attrs.len);
    try std.testing.expect(div.attrs[0].is_event);
    try std.testing.expect(div.attrs[1].is_event);
    try std.testing.expectEqualStrings("onmouseenter", div.attrs[0].name);
    try std.testing.expectEqualStrings("enter", div.attrs[0].event_handler.?);
    try std.testing.expectEqualStrings("onmouseleavecapture", div.attrs[1].name);
    try std.testing.expectEqualStrings("leave", div.attrs[1].event_handler.?);
}

test "parser accepts additional React DOM event handler references" {
    const source =
        \\<Component name="Events">
        \\  <div onScroll={handle} onAuxClick={handle}></div>
        \\  <details onToggle={handle} onCancel={handle} onClose={handle}></details>
        \\  <input onBeforeInput={handle} />
        \\  @handle:
        \\  L_ENTRY:
        \\    ret
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const div = program.components[0].dom_nodes[0];
    try std.testing.expect(div.attrs[0].is_event);
    try std.testing.expectEqualStrings("onscroll", div.attrs[0].name);
    try std.testing.expectEqualStrings("onauxclick", div.attrs[1].name);
    const details = program.components[0].dom_nodes[1];
    try std.testing.expectEqualStrings("ontoggle", details.attrs[0].name);
    try std.testing.expectEqualStrings("oncancel", details.attrs[1].name);
    try std.testing.expectEqualStrings("onclose", details.attrs[2].name);
    const input = program.components[0].dom_nodes[2];
    try std.testing.expectEqualStrings("onbeforeinput", input.attrs[0].name);
}

test "parser accepts DOM and component state refs and rejects unsupported refs" {
    const valid_source =
        \\<Component name="Refs">
        \\  <state>
        \\    input_ref = 0
        \\  </state>
        \\  <input ref={input_ref} />
        \\  !input_ref
        \\</Component>
    ;

    var valid_parser = Parser.init(std.testing.allocator, valid_source);
    var program = try valid_parser.parse();
    defer program.deinit();
    const input = program.components[0].dom_nodes[0];
    try std.testing.expectEqualStrings("ref", input.attrs[0].name);
    switch (input.attrs[0].value) {
        .interpolation => |expr| try std.testing.expectEqualStrings("input_ref", expr.expr),
        else => return error.TestUnexpectedResult,
    }

    const missing_source =
        \\<Component name="Refs">
        \\  <input ref={missing_ref} />
        \\</Component>
    ;
    var missing_parser = Parser.init(std.testing.allocator, missing_source);
    try std.testing.expectError(ParseError.InvalidAttribute, missing_parser.parse());

    const non_i64_source =
        \\<Component name="Refs">
        \\  <state>
        \\    input_ref = 0 as i1
        \\  </state>
        \\  <input ref={input_ref} />
        \\</Component>
    ;
    var non_i64_parser = Parser.init(std.testing.allocator, non_i64_source);
    try std.testing.expectError(ParseError.InvalidAttribute, non_i64_parser.parse());

    const component_ref_source =
        \\<Component name="Refs">
        \\  <state>
        \\    child_ref = 0 as ptr
        \\  </state>
        \\  <Child ref={child_ref} />
        \\</Component>
    ;
    var component_ref_parser = Parser.init(std.testing.allocator, component_ref_source);
    var component_ref_program = try component_ref_parser.parse();
    defer component_ref_program.deinit();
    const child = component_ref_program.components[0].dom_nodes[0];
    try std.testing.expect(child.is_user_component);
    try std.testing.expectEqualStrings("ref", child.attrs[0].name);

    const component_i64_ref_source =
        \\<Component name="Refs">
        \\  <state>
        \\    child_ref = 0
        \\  </state>
        \\  <Child ref={child_ref} />
        \\</Component>
    ;
    var component_i64_ref_parser = Parser.init(std.testing.allocator, component_i64_ref_source);
    try std.testing.expectError(ParseError.InvalidAttribute, component_i64_ref_parser.parse());

    const callback_ref_source =
        \\<Component name="Refs">
        \\  <input ref={capture_dom} />
        \\  <Child ref={capture_child} />
        \\  @capture_dom:
        \\  L_ENTRY:
        \\    ret
        \\  @capture_child:
        \\  L_ENTRY:
        \\    ret
        \\</Component>
    ;
    var callback_ref_parser = Parser.init(std.testing.allocator, callback_ref_source);
    var callback_ref_program = try callback_ref_parser.parse();
    defer callback_ref_program.deinit();
    switch (callback_ref_program.components[0].dom_nodes[0].attrs[0].value) {
        .interpolation => |expr| try std.testing.expectEqualStrings("capture_dom", expr.expr),
        else => return error.TestUnexpectedResult,
    }
    switch (callback_ref_program.components[0].dom_nodes[1].attrs[0].value) {
        .interpolation => |expr| try std.testing.expectEqualStrings("capture_child", expr.expr),
        else => return error.TestUnexpectedResult,
    }
}

test "parser preserves React keys as node metadata" {
    const source =
        \\<Component name="Keys">
        \\  <state>
        \\    id = 7
        \\  </state>
        \\  <ul>
        \\    <li key={id}>Item</li>
        \\  </ul>
        \\  <Badge key={id} count={id} />
        \\  !id
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const li = program.components[0].dom_nodes[1];
    try std.testing.expect(li.key != null);
    try std.testing.expectEqualStrings("id", li.key.?.expr);
    try std.testing.expectEqual(@as(usize, 0), li.attrs.len);

    const badge = program.components[0].dom_nodes[2];
    try std.testing.expect(badge.key != null);
    try std.testing.expectEqualStrings("id", badge.key.?.expr);
    try std.testing.expectEqual(@as(usize, 1), badge.attrs.len);
    try std.testing.expectEqualStrings("count", badge.attrs[0].name);

    const invalid_source =
        \\<Component name="Keys">
        \\  <li key="literal">Item</li>
        \\</Component>
    ;
    var invalid_parser = Parser.init(std.testing.allocator, invalid_source);
    try std.testing.expectError(ParseError.InvalidAttribute, invalid_parser.parse());
}

test "parser rejects complex React-style event expressions" {
    const source =
        \\<Component name="Events">
        \\  <button onClick={inc()}>+1</button>
        \\  @inc:
        \\  L_ENTRY:
        \\    ret
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    try std.testing.expectError(ParseError.InvalidEventName, parser.parse());
}

test "parser lowers static React style object attrs to CSS text" {
    const source =
        \\<Component name="Styled">
        \\  <div style={{ display: "grid", gap: "8px", lineHeight: 1.5, backgroundColor: "red" }}></div>
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const div = program.components[0].dom_nodes[0];
    try std.testing.expectEqualStrings("style", div.attrs[0].name);
    switch (div.attrs[0].value) {
        .literal => |lit| try std.testing.expectEqualStrings("display: grid; gap: 8px; line-height: 1.5; background-color: red; ", lit),
        else => return error.TestUnexpectedResult,
    }
}

test "parser rejects unsafe static React style object values" {
    const source =
        \\<Component name="Styled">
        \\  <div style={{ backgroundImage: "javascript:alert(1)" }}></div>
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    try std.testing.expectError(ParseError.InvalidAttribute, parser.parse());
}

test "parser accepts safe static dangerouslySetInnerHTML object attrs" {
    const source =
        \\<Component name="HtmlLab">
        \\  <div dangerouslySetInnerHTML={{ __html: "<strong>Trusted</strong>" }}></div>
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const div = program.components[0].dom_nodes[0];
    try std.testing.expectEqualStrings("dangerouslySetInnerHTML", div.attrs[0].name);
    switch (div.attrs[0].value) {
        .literal => |lit| try std.testing.expectEqualStrings("<strong>Trusted</strong>", lit),
        else => return error.TestUnexpectedResult,
    }
}

test "parser rejects unsafe dangerouslySetInnerHTML object attrs" {
    const source =
        \\<Component name="HtmlLab">
        \\  <div dangerouslySetInnerHTML={{ __html: "<img src=x onerror=alert(1)>" }}></div>
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    try std.testing.expectError(ParseError.InvalidAttribute, parser.parse());
}

test "parser accepts React Fragment tags as intrinsic nodes" {
    const source =
        \\<Component name="Fragments">
        \\  <Fragment><span>A</span></Fragment>
        \\  <React.Fragment><span>B</span></React.Fragment>
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const component = program.components[0];
    try std.testing.expectEqual(@as(usize, 4), component.dom_nodes.len);
    try std.testing.expectEqualStrings("Fragment", component.dom_nodes[0].tag);
    try std.testing.expect(!component.dom_nodes[0].is_user_component);
    try std.testing.expectEqualStrings("React.Fragment", component.dom_nodes[2].tag);
    try std.testing.expect(!component.dom_nodes[2].is_user_component);
}

test "parser accepts React shorthand Fragment tags" {
    const source =
        \\<Component name="Fragments">
        \\  <><span>A</span><span>B</span></>
        \\</Component>
    ;

    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    const component = program.components[0];
    try std.testing.expectEqual(@as(usize, 3), component.dom_nodes.len);
    try std.testing.expectEqualStrings("Fragment", component.dom_nodes[0].tag);
    try std.testing.expect(!component.dom_nodes[0].is_user_component);
    try std.testing.expectEqual(@as(usize, 2), component.dom_nodes[0].children.len);
}

test "parser rejects dangerous DOM attrs" {
    const source =
        \\<Component name="Unsafe">
        \\  <div innerHTML="<img src=x>"></div>
        \\</Component>
    ;
    var parser = Parser.init(std.testing.allocator, source);
    try std.testing.expectError(ParseError.InvalidAttribute, parser.parse());
}

test "parser marks ffi wrapper handlers" {
    const source =
        \\<Component name="Bridge">
        \\  <div></div>
        \\  @ffi_wrapper call_dom:
        \\  L_ENTRY:
        \\    raw = *state
        \\    return raw
        \\</Component>
    ;
    var parser = Parser.init(std.testing.allocator, source);
    var program = try parser.parse();
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 1), program.components.len);
    try std.testing.expectEqual(@as(usize, 1), program.components[0].handlers.len);
    try std.testing.expect(program.components[0].handlers[0].is_ffi_wrapper);
}
