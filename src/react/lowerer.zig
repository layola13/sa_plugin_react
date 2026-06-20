const std = @import("std");
const parser = @import("parser.zig");
const sla_handler_bridge = @import("sla_handler_bridge");

const Allocator = std.mem.Allocator;

pub const LowerError = error{
    OutOfMemory,
    UnknownNode,
    UnknownStateVar,
    UnknownHandler,
    InvalidInterpolation,
    InvalidTextExpression,
};

pub const SharedDeclMode = enum {
    none,
    full,
    component_externs,
    runtime_only,
};

pub const LowerOptions = struct {
    emit_shared_decls: bool = true,
    shared_decls: ?SharedDeclMode = null,
    emit_app_alias: bool = false,
};

const StringPool = struct {
    allocator: Allocator,
    items: std.ArrayList([]const u8),

    fn init(allocator: Allocator) StringPool {
        return .{
            .allocator = allocator,
            .items = std.ArrayList([]const u8).init(allocator),
        };
    }

    fn deinit(self: *StringPool) void {
        for (self.items.items) |item| self.allocator.free(item);
        self.items.deinit();
        self.* = undefined;
    }

    fn add(self: *StringPool, text: []const u8) !usize {
        try self.items.append(try self.allocator.dupe(u8, text));
        return self.items.items.len - 1;
    }
};

const StateSlot = struct {
    offset: usize,
    size: usize,
};

fn stateTypeName(ty: parser.StateType) []const u8 {
    return switch (ty) {
        .i1 => "i1",
        .i32 => "i32",
        .i64 => "i64",
        .f64 => "f64",
        .ptr => "ptr",
    };
}

fn stateInitValueExpr(init_expr: []const u8, ty: parser.StateType) []const u8 {
    const trimmed = std.mem.trim(u8, init_expr, " \t\r");
    if (std.mem.lastIndexOf(u8, trimmed, " as ")) |idx| {
        const suffix = std.mem.trim(u8, trimmed[idx + 4 ..], " \t\r");
        if (std.mem.eql(u8, suffix, stateTypeName(ty))) {
            return std.mem.trimRight(u8, trimmed[0..idx], " \t\r");
        }
    }
    return trimmed;
}

fn toSlaHandlerStateType(ty: parser.StateType) sla_handler_bridge.HandlerStateType {
    return switch (ty) {
        .i1 => .i1,
        .i32 => .i32,
        .i64 => .i64,
        .f64 => .f64,
        .ptr => .ptr,
    };
}

fn componentHasSlaHandlers(component: parser.Component) bool {
    for (component.handlers) |handler| {
        if (handler.language == .sla) return true;
    }
    return false;
}

fn releaseListContains(names: []const []const u8, needle: []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, name, needle)) return true;
    }
    return false;
}

const react_sla_ambient_bindings = [_]sla_handler_bridge.HandlerAmbientBinding{
    .{ .name = "checked", .ty = .i1 },
    .{ .name = "current_checked", .ty = .i1 },
    .{ .name = "default_prevented", .ty = .i1 },
    .{ .name = "key_repeat", .ty = .i1 },
    .{ .name = "pointer_primary", .ty = .i64 },
    .{ .name = "ref_value", .ty = .i64 },
    .{ .name = "target_value_i64", .ty = .i64 },
    .{ .name = "pointer_id", .ty = .i64 },
    .{ .name = "input_target", .ty = .i64 },
    .{ .name = "submit_target", .ty = .i64 },
    .{ .name = "related_target", .ty = .i64 },
    .{ .name = "wheel_delta_x", .ty = .i64 },
    .{ .name = "wheel_delta_y", .ty = .i64 },
    .{ .name = "wheel_delta_z", .ty = .i64 },
    .{ .name = "wheel_delta_mode", .ty = .i64 },
    .{ .name = "touches_len", .ty = .i64 },
    .{ .name = "touch_identifier", .ty = .i64 },
    .{ .name = "touch_client_x", .ty = .i64 },
    .{ .name = "touch_client_y", .ty = .i64 },
    .{ .name = "event_time_stamp", .ty = .i64 },
    .{ .name = "event_button", .ty = .i64 },
    .{ .name = "event_client_x", .ty = .i64 },
    .{ .name = "event_client_y", .ty = .i64 },
    .{ .name = "event_page_x", .ty = .i64 },
    .{ .name = "event_page_y", .ty = .i64 },
    .{ .name = "event_screen_x", .ty = .i64 },
    .{ .name = "event_screen_y", .ty = .i64 },
    .{ .name = "event_modifiers", .ty = .i64 },
    .{ .name = "current_value", .ty = .ptr },
    .{ .name = "input_target_name", .ty = .ptr },
    .{ .name = "input_target_id", .ty = .ptr },
    .{ .name = "submit_target_name", .ty = .ptr },
    .{ .name = "submit_target_id", .ty = .ptr },
    .{ .name = "pointer_type", .ty = .ptr },
    .{ .name = "selected_values", .ty = .ptr },
    .{ .name = "clipboard_text", .ty = .ptr },
    .{ .name = "drop_text", .ty = .ptr },
    .{ .name = "before_input_data", .ty = .ptr },
    .{ .name = "before_input_type", .ty = .ptr },
    .{ .name = "related_target_name", .ty = .ptr },
    .{ .name = "related_target_id", .ty = .ptr },
    .{ .name = "key_value", .ty = .ptr },
    .{ .name = "key_code", .ty = .ptr },
    .{ .name = "current_value_len", .ty = .i64 },
    .{ .name = "input_target_name_len", .ty = .i64 },
    .{ .name = "input_target_id_len", .ty = .i64 },
    .{ .name = "submit_target_name_len", .ty = .i64 },
    .{ .name = "submit_target_id_len", .ty = .i64 },
    .{ .name = "pointer_type_len", .ty = .i64 },
    .{ .name = "selected_values_len", .ty = .i64 },
    .{ .name = "clipboard_text_len", .ty = .i64 },
    .{ .name = "drop_text_len", .ty = .i64 },
    .{ .name = "before_input_data_len", .ty = .i64 },
    .{ .name = "before_input_type_len", .ty = .i64 },
    .{ .name = "related_target_name_len", .ty = .i64 },
    .{ .name = "related_target_id_len", .ty = .i64 },
    .{ .name = "key_value_len", .ty = .i64 },
    .{ .name = "key_code_len", .ty = .i64 },
};

fn f64BitsLiteral(init_expr: []const u8, ty: parser.StateType) LowerError!i64 {
    const value_text = stateInitValueExpr(init_expr, ty);
    const value = std.fmt.parseFloat(f64, value_text) catch return LowerError.InvalidTextExpression;
    return @bitCast(value);
}

const NodeSlots = struct {
    tag_const: usize,
    handle_slot: usize,
    text_slot_start: ?usize,
    text_slot_count: usize,
};

const RefCallbackKind = enum {
    dom,
    component,
};

const InterpolationValue = struct {
    name: []const u8,
    ty: parser.StateType,
};

const ComponentStateProp = struct {
    name: []const u8,
    state: parser.StateVar,
};

const StateStringSlice = struct {
    ptr_name: []const u8,
    len_name: []const u8,
};

const JsonStringTernaryKey = struct {
    condition_name: []const u8,
    true_key_json: []const u8,
    false_key_json: []const u8,
};

const JsonPtrStringTernaryKey = struct {
    condition_name: []const u8,
    true_state_name: []const u8,
    false_state_name: []const u8,
};

const JsonMixedStringTernaryKey = struct {
    condition_name: []const u8,
    true_branch: JsonStringKeyBranch,
    false_branch: JsonStringKeyBranch,
};

const JsonStringKeyBranch = union(enum) {
    state: []const u8,
    static_json: []const u8,
};

const PtrEqLiteralConditionItem = struct {
    state_name: []const u8,
    literal: []const u8,
};

const I64EqLiteralConditionItem = struct {
    state_name: []const u8,
    literal: i64,
};

const StaticEqConditionItem = union(enum) {
    truthy_state: []const u8,
    ptr_eq_literal: PtrEqLiteralConditionItem,
    i64_eq_literal: I64EqLiteralConditionItem,
};

const StaticEqConditionChain = struct {
    count: usize,
    items: [8]StaticEqConditionItem,
};

const StaticStringCondition = union(enum) {
    state_truthy: []const u8,
    and_truthy: struct {
        left_name: []const u8,
        right_name: []const u8,
    },
    ptr_eq_literal: struct {
        state_name: []const u8,
        literal: []const u8,
    },
    ptr_eq_literal_chain: struct {
        count: usize,
        items: [8]PtrEqLiteralConditionItem,
    },
    static_eq_chain: StaticEqConditionChain,
};

const StaticStringTernary = struct {
    condition: StaticStringCondition,
    true_text: []const u8,
    false_text: []const u8,
};

const JsonObjectSpreadTernary = struct {
    condition_name: []const u8,
    true_branch: JsonObjectSpreadBranch,
    false_branch: JsonObjectSpreadBranch,
};

const JsonObjectSpreadBranch = union(enum) {
    state: []const u8,
    static_json: []const u8,
};

const JsonStringValueTernary = struct {
    condition_name: []const u8,
    true_branch: JsonStringValueBranch,
    false_branch: JsonStringValueBranch,
};

const JsonStringValueBranch = union(enum) {
    state: []const u8,
    static_json: []const u8,
};

const JsonI64ValueTernary = struct {
    condition_name: []const u8,
    true_branch: JsonI64ValueBranch,
    false_branch: JsonI64ValueBranch,
};

const JsonI64ValueBranch = union(enum) {
    state: []const u8,
    literal: []const u8,
};

const JsonI32ValueTernary = struct {
    condition_name: []const u8,
    true_branch: JsonI32ValueBranch,
    false_branch: JsonI32ValueBranch,
};

const JsonI32ValueBranch = union(enum) {
    state: []const u8,
    literal: i32,
};

const JsonF64ValueTernary = struct {
    condition_name: []const u8,
    true_branch: JsonF64ValueBranch,
    false_branch: JsonF64ValueBranch,
};

const JsonF64ValueBranch = union(enum) {
    state: []const u8,
    literal_bits: i64,
};

const JsonI64TernaryKey = struct {
    condition_name: []const u8,
    true_branch: JsonI64ValueBranch,
    false_branch: JsonI64ValueBranch,
};

const JsonI32TernaryKey = struct {
    condition_name: []const u8,
    true_branch: JsonI32ValueBranch,
    false_branch: JsonI32ValueBranch,
};

const JsonF64TernaryKey = struct {
    condition_name: []const u8,
    true_branch: JsonF64ValueBranch,
    false_branch: JsonF64ValueBranch,
};

const JsonI1TernaryKey = struct {
    condition_name: []const u8,
    true_branch: JsonI1ValueBranch,
    false_branch: JsonI1ValueBranch,
};

const JsonI1ValueTernary = struct {
    condition_name: []const u8,
    true_branch: JsonI1ValueBranch,
    false_branch: JsonI1ValueBranch,
};

const JsonI1ValueBranch = union(enum) {
    state: []const u8,
    literal: bool,
};

const InterpolationExprLowerer = struct {
    owner: *SaxLowerer,
    out: *std.ArrayList(u8),
    expr: []const u8,
    prefix: []const u8,
    scratch_allocator: Allocator,
    pos: usize = 0,
    next_tmp: usize = 0,

    fn lower(self: *InterpolationExprLowerer) LowerError!InterpolationValue {
        self.skipSpace();
        if (self.pos >= self.expr.len) return LowerError.InvalidTextExpression;
        const value = try self.parseAddSub();
        self.skipSpace();
        if (self.pos != self.expr.len) return LowerError.InvalidTextExpression;
        return value;
    }

    fn parseAddSub(self: *InterpolationExprLowerer) LowerError!InterpolationValue {
        var left = try self.parseMulDiv();
        while (true) {
            self.skipSpace();
            if (self.consume('+')) {
                const right = try self.parseMulDiv();
                left = try self.emitBinary("add", left, right);
                continue;
            }
            if (self.consume('-')) {
                const right = try self.parseMulDiv();
                left = try self.emitBinary("sub", left, right);
                continue;
            }
            return left;
        }
    }

    fn parseMulDiv(self: *InterpolationExprLowerer) LowerError!InterpolationValue {
        var left = try self.parseUnary();
        while (true) {
            self.skipSpace();
            if (self.consume('*')) {
                const right = try self.parseUnary();
                left = try self.emitBinary("mul", left, right);
                continue;
            }
            if (self.consume('/')) {
                const right = try self.parseUnary();
                left = try self.emitBinary("sdiv", left, right);
                continue;
            }
            return left;
        }
    }

    fn parseUnary(self: *InterpolationExprLowerer) LowerError!InterpolationValue {
        self.skipSpace();
        if (self.consume('+')) return self.parseUnary();
        if (self.consume('-')) {
            const value = try self.parseUnary();
            return try self.emitBinary("sub", .{ .name = "0", .ty = .i64 }, value);
        }
        return self.parsePrimary();
    }

    fn parsePrimary(self: *InterpolationExprLowerer) LowerError!InterpolationValue {
        self.skipSpace();
        if (self.pos >= self.expr.len) return LowerError.InvalidTextExpression;

        if (self.consume('(')) {
            const value = try self.parseAddSub();
            self.skipSpace();
            if (!self.consume(')')) return LowerError.InvalidTextExpression;
            return value;
        }

        const c = self.expr[self.pos];
        if (std.ascii.isDigit(c)) return self.parseNumberLiteral();
        if (isIdentStart(c)) return self.parseStateLoad();
        return LowerError.InvalidTextExpression;
    }

    fn parseNumberLiteral(self: *InterpolationExprLowerer) LowerError!InterpolationValue {
        const start = self.pos;
        while (self.pos < self.expr.len and std.ascii.isDigit(self.expr[self.pos])) : (self.pos += 1) {}
        if (self.pos == start) return LowerError.InvalidTextExpression;
        var is_float = false;
        if (self.pos < self.expr.len and self.expr[self.pos] == '.') {
            is_float = true;
            self.pos += 1;
            const frac_start = self.pos;
            while (self.pos < self.expr.len and std.ascii.isDigit(self.expr[self.pos])) : (self.pos += 1) {}
            if (self.pos == frac_start) return LowerError.InvalidTextExpression;
        }
        if (self.pos < self.expr.len and (self.expr[self.pos] == 'e' or self.expr[self.pos] == 'E')) {
            is_float = true;
            self.pos += 1;
            if (self.pos < self.expr.len and (self.expr[self.pos] == '+' or self.expr[self.pos] == '-')) self.pos += 1;
            const exp_start = self.pos;
            while (self.pos < self.expr.len and std.ascii.isDigit(self.expr[self.pos])) : (self.pos += 1) {}
            if (self.pos == exp_start) return LowerError.InvalidTextExpression;
        }
        return .{
            .name = if (is_float) (try self.emitF64Literal(self.expr[start..self.pos])).name else self.expr[start..self.pos],
            .ty = if (is_float) .f64 else .i64,
        };
    }

    fn emitF64Literal(self: *InterpolationExprLowerer, literal: []const u8) LowerError!InterpolationValue {
        const value = std.fmt.parseFloat(f64, literal) catch return LowerError.InvalidTextExpression;
        const bits: i64 = @bitCast(value);
        const bits_name = try self.nextName("f64_bits");
        try self.out.writer().print("  {s} = {d}\n", .{ bits_name, bits });
        return .{ .name = bits_name, .ty = .f64 };
    }

    fn parseStateLoad(self: *InterpolationExprLowerer) LowerError!InterpolationValue {
        const start = self.pos;
        self.pos += 1;
        while (self.pos < self.expr.len and isIdentChar(self.expr[self.pos])) : (self.pos += 1) {}
        const name = self.expr[start..self.pos];
        const idx = self.owner.stateVarIndex(name) orelse return LowerError.UnknownStateVar;
        const state_ty = self.owner.component.state_vars[idx].ty;
        if (state_ty == .ptr) return LowerError.InvalidTextExpression;

        const dest = try self.nextName("load");
        const slot_name = try self.owner.stateSlotConstName(name);
        defer self.owner.allocator.free(slot_name);
        switch (state_ty) {
            .i64 => {
                try self.out.writer().print("  {s} = load state+{s} as i64\n", .{ dest, slot_name });
                return .{ .name = dest, .ty = state_ty };
            },
            .f64 => {
                try self.out.writer().print("  {s} = load state+{s} as i64\n", .{ dest, slot_name });
                return .{ .name = dest, .ty = state_ty };
            },
            .i32, .i1 => {
                try self.out.writer().print("  {s} = load state+{s} as {s}\n", .{ dest, slot_name, stateTypeName(state_ty) });
                const widened = try self.nextName("wide");
                const op = if (state_ty == .i1) "zext" else "sext";
                try self.out.writer().print("  {s} = {s} {s} as i64\n", .{ widened, op, dest });
                return .{ .name = widened, .ty = .i64 };
            },
            .ptr => unreachable,
        }
    }

    fn emitBinary(self: *InterpolationExprLowerer, op: []const u8, left: InterpolationValue, right: InterpolationValue) LowerError!InterpolationValue {
        if (left.ty != .i64 or right.ty != .i64) return LowerError.InvalidTextExpression;
        const dest = try self.nextName("op");
        try self.out.writer().print("  {s} = {s} {s}, {s}\n", .{ dest, op, left.name, right.name });
        return .{ .name = dest, .ty = .i64 };
    }

    fn nextName(self: *InterpolationExprLowerer, kind: []const u8) LowerError![]const u8 {
        const name = try std.fmt.allocPrint(self.scratch_allocator, "{s}_{s}_{d}", .{ self.prefix, kind, self.next_tmp });
        self.next_tmp += 1;
        return name;
    }

    fn skipSpace(self: *InterpolationExprLowerer) void {
        while (self.pos < self.expr.len and std.ascii.isWhitespace(self.expr[self.pos])) : (self.pos += 1) {}
    }

    fn consume(self: *InterpolationExprLowerer, expected: u8) bool {
        if (self.pos >= self.expr.len or self.expr[self.pos] != expected) return false;
        self.pos += 1;
        return true;
    }

    fn isIdentStart(c: u8) bool {
        return std.ascii.isAlphabetic(c) or c == '_';
    }

    fn isIdentChar(c: u8) bool {
        return std.ascii.isAlphanumeric(c) or c == '_';
    }
};

fn attrLiteralValue(node: parser.DomNode, attr_name: []const u8) ?[]const u8 {
    for (node.attrs) |attr| {
        if (!std.mem.eql(u8, attr.name, attr_name)) continue;
        return switch (attr.value) {
            .literal => |lit| lit,
            else => null,
        };
    }
    return null;
}

fn inputTypeUsesNativeChange(input_type: []const u8) bool {
    return std.ascii.eqlIgnoreCase(input_type, "checkbox") or
        std.ascii.eqlIgnoreCase(input_type, "radio") or
        std.ascii.eqlIgnoreCase(input_type, "file");
}

fn isCaptureEventAttr(attr_name: []const u8) bool {
    return std.mem.startsWith(u8, attr_name, "on") and std.mem.endsWith(u8, attr_name, "capture");
}

fn eventBaseAttrName(attr_name: []const u8) []const u8 {
    return if (isCaptureEventAttr(attr_name)) attr_name[0 .. attr_name.len - "capture".len] else attr_name;
}

fn domEventName(node: parser.DomNode, attr_name: []const u8) []const u8 {
    const base_attr = eventBaseAttrName(attr_name);
    if (std.mem.eql(u8, base_attr, "onclickaway")) return "clickaway";
    if (std.mem.eql(u8, base_attr, "ondoubleclick")) return "dblclick";
    if (std.mem.eql(u8, base_attr, "onchange")) {
        if (std.mem.eql(u8, node.tag, "textarea")) return "input";
        if (std.mem.eql(u8, node.tag, "select")) return "change";
        if (std.mem.eql(u8, node.tag, "input")) {
            const input_type = attrLiteralValue(node, "type") orelse "text";
            return if (inputTypeUsesNativeChange(input_type)) "change" else "input";
        }
    }
    if (std.mem.startsWith(u8, base_attr, "on") and base_attr.len > 2) {
        return base_attr[2..];
    }
    return base_attr;
}

fn domBoolPropName(attr_name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, attr_name, "hidden")) return "hidden";
    if (std.mem.eql(u8, attr_name, "inert")) return "inert";
    if (std.mem.eql(u8, attr_name, "draggable")) return "draggable";
    if (std.mem.eql(u8, attr_name, "controls")) return "controls";
    if (std.mem.eql(u8, attr_name, "muted")) return "muted";
    if (std.mem.eql(u8, attr_name, "loop")) return "loop";
    if (std.mem.eql(u8, attr_name, "autoplay")) return "autoplay";
    if (std.mem.eql(u8, attr_name, "playsinline")) return "playsInline";
    if (std.mem.eql(u8, attr_name, "disablePictureInPicture")) return "disablePictureInPicture";
    if (std.mem.eql(u8, attr_name, "disableRemotePlayback")) return "disableRemotePlayback";
    if (std.mem.eql(u8, attr_name, "novalidate")) return "noValidate";
    if (std.mem.eql(u8, attr_name, "formnovalidate")) return "formNoValidate";
    if (std.mem.eql(u8, attr_name, "reversed")) return "reversed";
    if (std.mem.eql(u8, attr_name, "default")) return "default";
    if (std.mem.eql(u8, attr_name, "itemscope")) return "itemScope";
    if (std.mem.eql(u8, attr_name, "ismap")) return "isMap";
    return null;
}

fn reactComponentPropAlias(attr_name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, attr_name, "class")) return "className";
    if (std.mem.eql(u8, attr_name, "for")) return "htmlFor";
    if (std.mem.eql(u8, attr_name, "autofocus")) return "autoFocus";
    if (std.mem.eql(u8, attr_name, "autoplay")) return "autoPlay";
    if (std.mem.eql(u8, attr_name, "playsinline")) return "playsInline";
    if (std.mem.eql(u8, attr_name, "autocomplete")) return "autoComplete";
    if (std.mem.eql(u8, attr_name, "accept-charset")) return "acceptCharset";
    if (std.mem.eql(u8, attr_name, "enctype")) return "encType";
    if (std.mem.eql(u8, attr_name, "formaction")) return "formAction";
    if (std.mem.eql(u8, attr_name, "formenctype")) return "formEncType";
    if (std.mem.eql(u8, attr_name, "formmethod")) return "formMethod";
    if (std.mem.eql(u8, attr_name, "formnovalidate")) return "formNoValidate";
    if (std.mem.eql(u8, attr_name, "formtarget")) return "formTarget";
    if (std.mem.eql(u8, attr_name, "dirname")) return "dirName";
    if (std.mem.eql(u8, attr_name, "accesskey")) return "accessKey";
    if (std.mem.eql(u8, attr_name, "tabindex")) return "tabIndex";
    if (std.mem.eql(u8, attr_name, "rowspan")) return "rowSpan";
    if (std.mem.eql(u8, attr_name, "colspan")) return "colSpan";
    if (std.mem.eql(u8, attr_name, "charset")) return "charSet";
    if (std.mem.eql(u8, attr_name, "http-equiv")) return "httpEquiv";
    if (std.mem.eql(u8, attr_name, "datetime")) return "dateTime";
    if (std.mem.eql(u8, attr_name, "inputmode")) return "inputMode";
    if (std.mem.eql(u8, attr_name, "enterkeyhint")) return "enterKeyHint";
    if (std.mem.eql(u8, attr_name, "autocapitalize")) return "autoCapitalize";
    if (std.mem.eql(u8, attr_name, "autocorrect")) return "autoCorrect";
    if (std.mem.eql(u8, attr_name, "maxlength")) return "maxLength";
    if (std.mem.eql(u8, attr_name, "minlength")) return "minLength";
    if (std.mem.eql(u8, attr_name, "novalidate")) return "noValidate";
    if (std.mem.eql(u8, attr_name, "readonly")) return "readOnly";
    if (std.mem.eql(u8, attr_name, "srcset")) return "srcSet";
    if (std.mem.eql(u8, attr_name, "srclang")) return "srcLang";
    if (std.mem.eql(u8, attr_name, "imagesrcset")) return "imageSrcSet";
    if (std.mem.eql(u8, attr_name, "imagesizes")) return "imageSizes";
    if (std.mem.eql(u8, attr_name, "longdesc")) return "longDesc";
    if (std.mem.eql(u8, attr_name, "hreflang")) return "hrefLang";
    if (std.mem.eql(u8, attr_name, "usemap")) return "useMap";
    if (std.mem.eql(u8, attr_name, "ismap")) return "isMap";
    if (std.mem.eql(u8, attr_name, "referrerpolicy")) return "referrerPolicy";
    if (std.mem.eql(u8, attr_name, "contenteditable")) return "contentEditable";
    if (std.mem.eql(u8, attr_name, "spellcheck")) return "spellCheck";
    if (std.mem.eql(u8, attr_name, "crossorigin")) return "crossOrigin";
    if (std.mem.eql(u8, attr_name, "itemprop")) return "itemProp";
    if (std.mem.eql(u8, attr_name, "itemscope")) return "itemScope";
    if (std.mem.eql(u8, attr_name, "itemtype")) return "itemType";
    if (std.mem.eql(u8, attr_name, "itemid")) return "itemID";
    if (std.mem.eql(u8, attr_name, "itemref")) return "itemRef";
    if (std.mem.eql(u8, attr_name, "font-size")) return "fontSize";
    if (std.mem.eql(u8, attr_name, "aria-label")) return "ariaLabel";
    if (std.mem.eql(u8, attr_name, "aria-labelledby")) return "ariaLabelledby";
    if (std.mem.eql(u8, attr_name, "aria-describedby")) return "ariaDescribedby";
    return null;
}

fn nodeUsesGenericBoolProperty(node: parser.DomNode, attr_name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, attr_name, "disabled")) {
        return if (std.mem.eql(u8, node.tag, "link")) "disabled" else null;
    }
    const prop_name = domBoolPropName(attr_name) orelse return null;
    if (std.mem.eql(u8, attr_name, "controls") or
        std.mem.eql(u8, attr_name, "muted") or
        std.mem.eql(u8, attr_name, "loop") or
        std.mem.eql(u8, attr_name, "autoplay") or
        std.mem.eql(u8, attr_name, "playsinline") or
        std.mem.eql(u8, attr_name, "disablePictureInPicture") or
        std.mem.eql(u8, attr_name, "disableRemotePlayback"))
    {
        if (!std.mem.eql(u8, node.tag, "audio") and !std.mem.eql(u8, node.tag, "video")) return null;
    }
    if (std.mem.eql(u8, attr_name, "novalidate") and !std.mem.eql(u8, node.tag, "form")) return null;
    if (std.mem.eql(u8, attr_name, "formnovalidate") and !std.mem.eql(u8, node.tag, "button") and !std.mem.eql(u8, node.tag, "input")) return null;
    if (std.mem.eql(u8, attr_name, "reversed") and !std.mem.eql(u8, node.tag, "ol")) return null;
    if (std.mem.eql(u8, attr_name, "default") and !std.mem.eql(u8, node.tag, "track")) return null;
    if (std.mem.eql(u8, attr_name, "ismap") and !std.mem.eql(u8, node.tag, "img")) return null;
    return prop_name;
}

pub const SaxLowerer = struct {
    allocator: Allocator,
    component: parser.Component,
    program_components: []const parser.Component,
    state_slots: []StateSlot,
    state_size: usize,
    node_slots: []NodeSlots,
    dom_slot_count: usize,
    string_pool: StringPool,
    event_handlers: std.StringHashMap([]const u8),
    label_scope_counter: usize,

    pub fn init(allocator: Allocator, component: parser.Component) !SaxLowerer {
        return initWithProgram(allocator, &.{}, component);
    }

    pub fn initWithProgram(allocator: Allocator, program_components: []const parser.Component, component: parser.Component) !SaxLowerer {
        var pool = StringPool.init(allocator);
        errdefer pool.deinit();

        const state_slots = try allocator.alloc(StateSlot, component.state_vars.len);
        errdefer allocator.free(state_slots);
        var state_size: usize = 0;
        for (component.state_vars, 0..) |sv, idx| {
            const size = stateVarSize(sv.ty);
            state_slots[idx] = .{ .offset = state_size, .size = size };
            state_size += size;
        }

        const node_slots = try allocator.alloc(NodeSlots, component.dom_nodes.len);
        errdefer allocator.free(node_slots);
        var dom_slot_count: usize = 0;
        for (component.dom_nodes, 0..) |node, idx| {
            const tag_const = try pool.add(nodeCreateTag(node));
            const text_slot_count = textNodeSlotCount(node);
            const text_slot_start: ?usize = if (text_slot_count == 0) null else dom_slot_count + 1;
            node_slots[idx] = .{
                .tag_const = tag_const,
                .handle_slot = dom_slot_count,
                .text_slot_start = text_slot_start,
                .text_slot_count = text_slot_count,
            };
            dom_slot_count += 1 + text_slot_count;
        }

        var event_handlers = std.StringHashMap([]const u8).init(allocator);
        errdefer event_handlers.deinit();
        for (component.handlers) |handler| {
            try event_handlers.put(handler.name, handler.body);
        }

        return .{
            .allocator = allocator,
            .component = component,
            .program_components = program_components,
            .state_slots = state_slots,
            .state_size = state_size,
            .node_slots = node_slots,
            .dom_slot_count = dom_slot_count,
            .string_pool = pool,
            .event_handlers = event_handlers,
            .label_scope_counter = 0,
        };
    }

    pub fn deinit(self: *SaxLowerer) void {
        self.event_handlers.deinit();
        self.string_pool.deinit();
        self.allocator.free(self.node_slots);
        self.allocator.free(self.state_slots);
        self.* = undefined;
    }

    fn allocLabelPrefix(self: *SaxLowerer, prefix: []const u8) ![]u8 {
        const scoped = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ prefix, self.label_scope_counter });
        self.label_scope_counter += 1;
        for (scoped) |*c| {
            if (!std.ascii.isAlphanumeric(c.*) and c.* != '_') c.* = '_';
        }
        return scoped;
    }

    fn stateVarIndex(self: *const SaxLowerer, name: []const u8) ?usize {
        for (self.component.state_vars, 0..) |sv, idx| {
            if (std.mem.eql(u8, sv.name, name)) return idx;
        }
        return null;
    }

    fn componentByName(self: *const SaxLowerer, name: []const u8) ?parser.Component {
        if (std.mem.eql(u8, self.component.name, name)) return self.component;
        for (self.program_components) |component| {
            if (std.mem.eql(u8, component.name, name)) return component;
        }
        return null;
    }

    fn componentStateVar(self: *const SaxLowerer, component_name: []const u8, state_name: []const u8) ?parser.StateVar {
        const component = self.componentByName(component_name) orelse return null;
        for (component.state_vars) |sv| {
            if (std.mem.eql(u8, sv.name, state_name)) return sv;
        }
        return null;
    }

    fn componentStateSlotOffset(self: *const SaxLowerer, component_name: []const u8, state_name: []const u8) ?usize {
        const component = self.componentByName(component_name) orelse return null;
        var offset: usize = 0;
        for (component.state_vars) |sv| {
            if (std.mem.eql(u8, sv.name, state_name)) return offset;
            offset += stateVarSize(sv.ty);
        }
        return null;
    }

    fn componentStateProp(self: *const SaxLowerer, component_name: []const u8, attr_name: []const u8) ?ComponentStateProp {
        if (self.componentStateVar(component_name, attr_name)) |state| {
            return .{ .name = attr_name, .state = state };
        }
        const alias = reactComponentPropAlias(attr_name) orelse return null;
        if (self.componentStateVar(component_name, alias)) |state| {
            return .{ .name = alias, .state = state };
        }
        return null;
    }

    fn componentStateSlotConstName(self: *const SaxLowerer, component_name: []const u8, state_name: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "{s}_{s}", .{ component_name, state_name });
    }

    fn componentPreferredOnChangeEvent(self: *const SaxLowerer, component_name: []const u8) ?[]const u8 {
        return self.componentPreferredOnChangeEventDepth(component_name, 0);
    }

    fn componentPreferredOnChangeEventDepth(self: *const SaxLowerer, component_name: []const u8, depth: usize) ?[]const u8 {
        if (depth > 8) return null;
        const component = self.componentByName(component_name) orelse return null;
        for (component.root_nodes) |root_idx| {
            if (self.nodePreferredOnChangeEvent(component, root_idx, depth)) |event_name| return event_name;
        }
        return null;
    }

    fn nodePreferredOnChangeEvent(self: *const SaxLowerer, component: parser.Component, node_idx: usize, depth: usize) ?[]const u8 {
        const node = component.dom_nodes[node_idx];
        if (std.mem.eql(u8, node.tag, "textarea")) return "input";
        if (std.mem.eql(u8, node.tag, "select")) return "change";
        if (std.mem.eql(u8, node.tag, "input")) {
            const input_type = attrLiteralValue(node, "type") orelse "text";
            return if (inputTypeUsesNativeChange(input_type)) "change" else "input";
        }
        if (node.is_user_component) {
            if (self.componentPreferredOnChangeEventDepth(node.tag, depth + 1)) |event_name| return event_name;
        }
        for (node.children) |child| {
            switch (child) {
                .node_index => |child_idx| if (self.nodePreferredOnChangeEvent(component, child_idx, depth)) |event_name| return event_name,
                else => {},
            }
        }
        return null;
    }

    fn isContextPropListDelimiter(c: u8) bool {
        return std.ascii.isWhitespace(c) or c == ',';
    }

    fn slotContextProps(component: parser.Component) ?[]const u8 {
        for (component.dom_nodes) |node| {
            if (!std.mem.eql(u8, node.tag, "Slot")) continue;
            for (node.attrs) |attr| {
                if (!std.mem.eql(u8, attr.name, "contextProps")) continue;
                return switch (attr.value) {
                    .literal => |lit| lit,
                    else => null,
                };
            }
        }
        return null;
    }

    fn slotContextScope(component: parser.Component) ?[]const u8 {
        for (component.dom_nodes) |node| {
            if (!std.mem.eql(u8, node.tag, "Slot")) continue;
            for (node.attrs) |attr| {
                if (!std.mem.eql(u8, attr.name, "contextScope")) continue;
                return switch (attr.value) {
                    .literal => |lit| lit,
                    else => null,
                };
            }
        }
        return null;
    }

    fn firstSlotNodeIndex(component: parser.Component) ?usize {
        for (component.dom_nodes, 0..) |node, idx| {
            if (std.mem.eql(u8, node.tag, "Slot")) return idx;
        }
        return null;
    }

    fn nodeDepthToTarget(component: parser.Component, root_idx: usize, target_idx: usize) ?usize {
        if (root_idx == target_idx) return 0;
        const node = component.dom_nodes[root_idx];
        for (node.children) |child| {
            switch (child) {
                .node_index => |child_idx| {
                    if (nodeDepthToTarget(component, child_idx, target_idx)) |depth| return depth + 1;
                },
                .text => {},
            }
        }
        return null;
    }

    fn componentForwardedSlotProviderComponentDepth(self: *const SaxLowerer, component: parser.Component, depth: usize) ?parser.Component {
        if (depth > 8) return null;
        const slot_idx = firstSlotNodeIndex(component) orelse return null;
        var best_component: ?parser.Component = null;
        var best_depth: usize = std.math.maxInt(usize);
        for (component.dom_nodes, 0..) |node, idx| {
            if (!node.is_user_component) continue;
            const distance = nodeDepthToTarget(component, idx, slot_idx) orelse continue;
            if (distance == 0 or distance >= best_depth) continue;
            const child_component = self.componentByName(node.tag) orelse continue;
            if (self.componentEffectiveSlotContextPropsDepth(child_component, depth + 1) == null) continue;
            best_component = child_component;
            best_depth = distance;
        }
        return best_component;
    }

    fn componentEffectiveSlotContextProps(self: *const SaxLowerer, component: parser.Component) ?[]const u8 {
        return self.componentEffectiveSlotContextPropsDepth(component, 0);
    }

    fn componentEffectiveSlotContextPropsDepth(self: *const SaxLowerer, component: parser.Component, depth: usize) ?[]const u8 {
        if (slotContextProps(component)) |props| return props;
        if (depth > 8) return null;
        const provider_component = self.componentForwardedSlotProviderComponentDepth(component, depth) orelse return null;
        return self.componentEffectiveSlotContextPropsDepth(provider_component, depth + 1);
    }

    fn componentEffectiveSlotContextScope(self: *const SaxLowerer, component: parser.Component) ?[]const u8 {
        return self.componentEffectiveSlotContextScopeDepth(component, 0);
    }

    fn componentEffectiveSlotContextScopeDepth(self: *const SaxLowerer, component: parser.Component, depth: usize) ?[]const u8 {
        if (slotContextScope(component)) |scope| return scope;
        if (depth > 8) return null;
        const provider_component = self.componentForwardedSlotProviderComponentDepth(component, depth) orelse return null;
        return self.componentEffectiveSlotContextScopeDepth(provider_component, depth + 1);
    }

    fn componentHasAnyStatePropInList(self: *const SaxLowerer, component_name: []const u8, props: []const u8) bool {
        var start: usize = 0;
        while (start < props.len) {
            while (start < props.len and isContextPropListDelimiter(props[start])) start += 1;
            if (start >= props.len) break;
            var end = start;
            while (end < props.len and !isContextPropListDelimiter(props[end])) end += 1;
            if (self.componentStateProp(component_name, props[start..end]) != null) return true;
            start = end;
        }
        return false;
    }

    fn nodeProvidesContextProps(self: *const SaxLowerer, node: parser.DomNode) bool {
        if (!node.is_user_component) return false;
        const component = self.componentByName(node.tag) orelse return false;
        const props = self.componentEffectiveSlotContextProps(component) orelse return false;
        return self.componentHasAnyStatePropInList(node.tag, props);
    }

    fn nodeProvidesDescendantContextProps(self: *const SaxLowerer, node: parser.DomNode) bool {
        if (!self.nodeProvidesContextProps(node)) return false;
        const component = self.componentByName(node.tag) orelse return false;
        const scope = self.componentEffectiveSlotContextScope(component) orelse return false;
        return std.mem.eql(u8, scope, "descendants");
    }

    fn childHasExplicitComponentProp(self: *const SaxLowerer, child_node: parser.DomNode, state_name: []const u8) bool {
        for (child_node.attrs) |attr| {
            if (attr.is_event) continue;
            if (isRefAttr(attr.name) or isKeyAttr(attr.name)) continue;
            const target_prop = self.componentStateProp(child_node.tag, attr.name) orelse continue;
            if (std.mem.eql(u8, target_prop.name, state_name)) return true;
        }
        return false;
    }

    fn stateSlot(self: *const SaxLowerer, name: []const u8) !StateSlot {
        const idx = self.stateVarIndex(name) orelse return LowerError.UnknownStateVar;
        return self.state_slots[idx];
    }

    fn stateVar(self: *const SaxLowerer, name: []const u8) ?parser.StateVar {
        const idx = self.stateVarIndex(name) orelse return null;
        return self.component.state_vars[idx];
    }

    fn stateLenVarName(self: *const SaxLowerer, state_name: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "{s}_len", .{state_name});
    }

    fn nodeIndex(self: *const SaxLowerer, alias: []const u8) ?usize {
        for (self.component.dom_nodes, 0..) |node, idx| {
            if (std.mem.eql(u8, node.alias, alias)) return idx;
        }
        return null;
    }

    fn escapeText(allocator: Allocator, text: []const u8) ![]const u8 {
        var out = std.ArrayList(u8).init(allocator);
        errdefer out.deinit();
        for (text) |c| {
            switch (c) {
                '\\' => try out.appendSlice("\\\\"),
                '"' => try out.appendSlice("\\\""),
                '\n' => try out.appendSlice("\\n"),
                '\r' => try out.appendSlice("\\r"),
                '\t' => try out.appendSlice("\\t"),
                else => try out.append(c),
            }
        }
        return try out.toOwnedSlice();
    }

    fn lowercaseName(allocator: Allocator, text: []const u8) ![]const u8 {
        const out = try allocator.dupe(u8, text);
        for (out) |*c| c.* = std.ascii.toLower(c.*);
        return out;
    }

    fn stringConstName(self: *const SaxLowerer, kind: []const u8, index: usize) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_{s}_{d}", .{ self.component.name, kind, index });
    }

    fn routeConstName(self: *const SaxLowerer, index: usize, kind: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_route_{s}_{d}", .{ self.component.name, kind, index });
    }

    fn stateVarSize(ty: parser.StateType) usize {
        return switch (ty) {
            .i1, .i32, .i64, .f64, .ptr => 8,
        };
    }

    fn componentStem(self: *const SaxLowerer) ![]const u8 {
        return try lowercaseName(self.allocator, self.component.name);
    }

    fn stateSlotConstName(self: *const SaxLowerer, state_name: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "{s}_{s}", .{ self.component.name, state_name });
    }

    fn stateSizeConstName(self: *const SaxLowerer) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "{s}_SIZE", .{self.component.name});
    }

    fn domSizeConstName(self: *const SaxLowerer) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "{s}_dom_SIZE", .{self.component.name});
    }

    fn ctxSizeConstName(self: *const SaxLowerer) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "{s}_CTX_SIZE", .{self.component.name});
    }

    fn ctxStateOffsetConstName(self: *const SaxLowerer) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "{s}_CTX_state", .{self.component.name});
    }

    fn ctxDomOffsetConstName(self: *const SaxLowerer) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "{s}_CTX_dom", .{self.component.name});
    }

    fn handlerExportName(self: *const SaxLowerer, handler_name: []const u8) ![]const u8 {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_{s}", .{ stem, handler_name });
    }

    fn handlerImplName(self: *const SaxLowerer, handler_name: []const u8) ![]const u8 {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_{s}_ffi", .{ stem, handler_name });
    }

    fn refCallbackImplName(self: *const SaxLowerer, handler_name: []const u8, kind: RefCallbackKind) ![]const u8 {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        const suffix = switch (kind) {
            .dom => "dom_ref",
            .component => "component_ref",
        };
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_{s}_{s}_ffi", .{ stem, handler_name, suffix });
    }

    fn lifecycleImplName(self: *const SaxLowerer, hook_name: []const u8) ![]const u8 {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_{s}_ffi", .{ stem, hook_name });
    }

    fn initImplName(self: *const SaxLowerer) ![]const u8 {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_init_ffi", .{stem});
    }

    fn renderImplName(self: *const SaxLowerer) ![]const u8 {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_render_ffi", .{stem});
    }

    fn mountImplName(self: *const SaxLowerer) ![]const u8 {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_mount_ffi", .{stem});
    }

    fn slotImplName(self: *const SaxLowerer) ![]const u8 {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_slot_ffi", .{stem});
    }

    fn rootImplName(self: *const SaxLowerer) ![]const u8 {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_root_ffi", .{stem});
    }

    fn stateSetterImplName(self: *const SaxLowerer, state_name: []const u8) ![]const u8 {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_set_{s}_ffi", .{ stem, state_name });
    }

    fn stringStateSetterImplName(self: *const SaxLowerer, state_name: []const u8) ![]const u8 {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_set_{s}_str_ffi", .{ stem, state_name });
    }

    fn destroyImplName(self: *const SaxLowerer) ![]const u8 {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_destroy_ffi", .{stem});
    }

    fn routerInitImplName(self: *const SaxLowerer) ![]const u8 {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_router_init_ffi", .{stem});
    }

    fn componentExportStem(self: *const SaxLowerer, component_name: []const u8) ![]const u8 {
        return try lowercaseName(self.allocator, component_name);
    }

    fn componentStateSetterName(self: *const SaxLowerer, component_name: []const u8, state_name: []const u8) ![]const u8 {
        const stem = try self.componentExportStem(component_name);
        defer self.allocator.free(stem);
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_set_{s}", .{ stem, state_name });
    }

    fn componentStringStateSetterName(self: *const SaxLowerer, component_name: []const u8, state_name: []const u8) ![]const u8 {
        const stem = try self.componentExportStem(component_name);
        defer self.allocator.free(stem);
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_set_{s}_str", .{ stem, state_name });
    }

    fn hostSelectorConstName(self: *const SaxLowerer) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_host_app", .{self.component.name});
    }

    fn stateSlotExpr(self: *const SaxLowerer, name: []const u8) ![]const u8 {
        return try self.stateSlotConstName(name);
    }

    fn stateAllocSize(self: *const SaxLowerer) usize {
        return @max(self.state_size, 8);
    }

    fn domAllocSize(self: *const SaxLowerer) usize {
        const bytes = self.dom_slot_count * 8;
        return @max(bytes, 8);
    }

    fn textPieceNeedsSeparateNode(piece: parser.TextPiece) bool {
        return switch (piece) {
            .text => |txt| txt.len != 0,
            .interpolation, .json_string_interpolation, .json_object_spread => true,
        };
    }

    fn projectedTextPieceNeedsSlot(piece: parser.TextPiece) bool {
        return textPieceNeedsSeparateNode(piece);
    }

    fn projectedTextPieceNeedsRender(piece: parser.TextPiece) bool {
        return switch (piece) {
            .text => false,
            .interpolation, .json_string_interpolation, .json_object_spread => true,
        };
    }

    fn projectedTextNodeSlotCount(node: parser.DomNode) usize {
        var text_count: usize = 0;
        for (node.children) |child| {
            switch (child) {
                .text => |piece| {
                    if (projectedTextPieceNeedsSlot(piece)) text_count += 1;
                },
                .node_index => {},
            }
        }
        return text_count;
    }

    fn textNodeSlotCount(node: parser.DomNode) usize {
        if (node.is_user_component) return projectedTextNodeSlotCount(node);
        return separateTextNodeCount(node);
    }

    fn separateTextNodeCount(node: parser.DomNode) usize {
        if (node.self_closing) return 0;
        if (std.mem.eql(u8, node.tag, "textarea")) return 0;
        if (nodeHasAttr(node, "dangerouslySetInnerHTML")) return 0;

        var has_node_child = false;
        var text_count: usize = 0;
        for (node.children) |child| {
            switch (child) {
                .node_index => has_node_child = true,
                .text => |piece| {
                    if (textPieceNeedsSeparateNode(piece)) text_count += 1;
                },
            }
        }
        return if (has_node_child) text_count else 0;
    }

    fn nodeTextBufferSize(self: *const SaxLowerer, node: parser.DomNode) usize {
        var size: usize = 1;
        for (node.children) |child| {
            switch (child) {
                .text => |piece| switch (piece) {
                    .text => |txt| size += txt.len,
                    .json_string_interpolation => size += 64,
                    .json_object_spread => size += 64,
                    .interpolation => |expr| {
                        if (simpleStateExprName(expr)) |name| {
                            if (self.stateVar(name)) |sv| {
                                if (sv.ty == .ptr) {
                                    size += sv.alloc_size orelse 64;
                                    continue;
                                }
                            }
                        }
                        size += 64;
                    },
                },
                else => {},
            }
        }
        return size;
    }

    fn templateBufferSize(self: *const SaxLowerer, pieces: []const parser.TextPiece) usize {
        var size: usize = 1;
        for (pieces) |piece| {
            switch (piece) {
                .text => |txt| size += txt.len,
                .json_string_interpolation => |expr| {
                    if (simpleStateExprName(expr)) |name| {
                        if (self.stateVar(name)) |sv| {
                            if (sv.ty == .ptr) {
                                size += (sv.alloc_size orelse 64) * 2 + 2;
                                continue;
                            }
                        }
                    }
                    size += 66;
                },
                .json_object_spread => |spread| {
                    if (simpleStateExprName(spread.expr)) |name| {
                        if (self.stateVar(name)) |sv| {
                            if (sv.ty == .ptr) {
                                size += (sv.alloc_size orelse 64) + 1;
                                continue;
                            }
                        }
                    }
                    size += 64;
                },
                .interpolation => |expr| {
                    if (self.parseStaticStringTernary(expr)) |ternary| {
                        size += @max(ternary.true_text.len, ternary.false_text.len);
                        continue;
                    }
                    if (simpleStateExprName(expr)) |name| {
                        if (self.stateVar(name)) |sv| {
                            if (sv.ty == .ptr) {
                                size += sv.alloc_size orelse 64;
                                continue;
                            }
                        }
                    }
                    size += 64;
                },
            }
        }
        return @max(size, 32);
    }

    fn jsonTemplateBufferSize(self: *const SaxLowerer, pieces: []const parser.TextPiece) usize {
        var size: usize = 1;
        for (pieces) |piece| {
            switch (piece) {
                .text => |txt| size += txt.len,
                .json_string_interpolation => |expr| {
                    if (simpleStateExprName(expr)) |name| {
                        if (self.stateVar(name)) |sv| {
                            if (sv.ty == .ptr) {
                                size += (sv.alloc_size orelse 64) * 2 + 2;
                                continue;
                            }
                        }
                    }
                    size += 66;
                },
                .json_object_spread => |spread| {
                    if (simpleStateExprName(spread.expr)) |name| {
                        if (self.stateVar(name)) |sv| {
                            if (sv.ty == .ptr) {
                                size += (sv.alloc_size orelse 64) + 1;
                                continue;
                            }
                        }
                    }
                    size += 64;
                },
                .interpolation => |expr| {
                    if (simpleStateExprName(expr)) |name| {
                        if (self.stateVar(name)) |sv| {
                            if (sv.ty == .ptr) {
                                size += (sv.alloc_size orelse 64) * 2 + 2;
                                continue;
                            }
                        }
                    }
                    size += 64;
                },
            }
        }
        return @max(size, 32);
    }

    fn stateValueExpr(self: *const SaxLowerer, var_name: []const u8) ![]const u8 {
        const slot = try self.stateSlot(var_name);
        return try std.fmt.allocPrint(self.allocator, "state+{d}", .{slot.offset});
    }

    fn appendConstDecls(self: *const SaxLowerer, out: *std.ArrayList(u8)) !void {
        for (self.string_pool.items.items, 0..) |text, idx| {
            const escaped = try escapeText(self.allocator, text);
            defer self.allocator.free(escaped);
            try out.writer().print("@const sax_{s}_{d} = utf8:\"{s}\"\n", .{ self.component.name, idx, escaped });
        }
        if (self.string_pool.items.items.len != 0) try out.writer().writeByte('\n');

        for (self.component.route_pages, 0..) |page, idx| {
            const path_const = try self.routeConstName(idx, "path");
            defer self.allocator.free(path_const);
            const component_const = try self.routeConstName(idx, "component");
            defer self.allocator.free(component_const);
            const escaped_path = try escapeText(self.allocator, page.path);
            defer self.allocator.free(escaped_path);
            const escaped_component = try escapeText(self.allocator, page.component);
            defer self.allocator.free(escaped_component);
            try out.writer().print("@const {s} = utf8:\"{s}\"\n", .{ path_const, escaped_path });
            try out.writer().print("@const {s} = utf8:\"{s}\"\n", .{ component_const, escaped_component });
        }
        if (self.component.route_pages.len != 0) try out.writer().writeByte('\n');

        var wrote_key_meta = false;
        for (self.component.dom_nodes) |node| {
            const key_expr = node.key orelse continue;
            const key_const = try self.nodeKeyConstName(node.alias);
            defer self.allocator.free(key_const);
            const escaped_key = try escapeText(self.allocator, key_expr.expr);
            defer self.allocator.free(escaped_key);
            try out.writer().print("@const {s} = utf8:\"{s}\"\n", .{ key_const, escaped_key });
            wrote_key_meta = true;
        }
        if (wrote_key_meta) try out.writer().writeByte('\n');

        const host_selector = try self.hostSelectorConstName();
        defer self.allocator.free(host_selector);
        try out.writer().print("@const {s} = utf8:\"#app\"\n", .{host_selector});
        try out.writer().writeByte('\n');
    }

    fn appendExternDecls(_: *const SaxLowerer, out: *std.ArrayList(u8)) !void {
        const decls = [_][]const u8{
            "@extern sax_dom_query(*sel_ptr: ptr, sel_len: i64) -> i64",
            "@extern sax_dom_query_all(*sel_ptr: ptr, sel_len: i64, *out_ptr: ptr, max_count: i64) -> i64",
            "@extern sax_dom_create(*tag_ptr: ptr, tag_len: i64) -> i64",
            "@extern sax_dom_create_text(*text_ptr: ptr, text_len: i64) -> i64",
            "@extern sax_dom_append_child(parent_h: i64, child_h: i64) -> void",
            "@extern sax_dom_remove_child(parent_h: i64, child_h: i64) -> void",
            "@extern sax_dom_remove_self(node_h: i64) -> void",
            "@extern sax_dom_insert_before(parent_h: i64, new_h: i64, ref_h: i64) -> void",
            "@extern sax_dom_set_text(node_h: i64, *text_ptr: ptr, text_len: i64) -> void",
            "@extern sax_dom_set_inner_html(node_h: i64, *html_ptr: ptr, html_len: i64) -> void",
            "@extern sax_dom_get_text(node_h: i64, *buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_dom_set_attr(node_h: i64, *key_ptr: ptr, key_len: i64, *val_ptr: ptr, val_len: i64) -> void",
            "@extern sax_dom_remove_attr(node_h: i64, *key_ptr: ptr, key_len: i64) -> void",
            "@extern sax_dom_get_attr(node_h: i64, *key_ptr: ptr, key_len: i64, *buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_dom_focus(node_h: i64) -> void",
            "@extern sax_dom_add_class(node_h: i64, *cls_ptr: ptr, cls_len: i64) -> void",
            "@extern sax_dom_remove_class(node_h: i64, *cls_ptr: ptr, cls_len: i64) -> void",
            "@extern sax_dom_toggle_class(node_h: i64, *cls_ptr: ptr, cls_len: i64, force: i1) -> i1",
            "@extern sax_dom_get_value(node_h: i64, *buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_dom_set_value(node_h: i64, *val_ptr: ptr, val_len: i64) -> void",
            "@extern sax_dom_get_checked(node_h: i64) -> i1",
            "@extern sax_dom_set_checked(node_h: i64, checked: i1) -> void",
            "@extern sax_dom_get_selected(node_h: i64) -> i1",
            "@extern sax_dom_set_selected(node_h: i64, selected: i1) -> void",
            "@extern sax_dom_get_multiple(node_h: i64) -> i1",
            "@extern sax_dom_set_multiple(node_h: i64, multiple: i1) -> void",
            "@extern sax_dom_get_disabled(node_h: i64) -> i1",
            "@extern sax_dom_set_disabled(node_h: i64, disabled: i1) -> void",
            "@extern sax_dom_get_readonly(node_h: i64) -> i1",
            "@extern sax_dom_set_readonly(node_h: i64, readonly: i1) -> void",
            "@extern sax_dom_get_required(node_h: i64) -> i1",
            "@extern sax_dom_set_required(node_h: i64, required: i1) -> void",
            "@extern sax_dom_get_open(node_h: i64) -> i1",
            "@extern sax_dom_set_open(node_h: i64, open: i1) -> void",
            "@extern sax_dom_set_translate(node_h: i64, *val_ptr: ptr, val_len: i64) -> void",
            "@extern sax_dom_get_bool_prop(node_h: i64, *prop_ptr: ptr, prop_len: i64) -> i1",
            "@extern sax_dom_set_bool_prop(node_h: i64, *prop_ptr: ptr, prop_len: i64, value: i1) -> void",
            "@extern sax_dom_get_str_prop(node_h: i64, *prop_ptr: ptr, prop_len: i64, *buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_dom_set_str_prop(node_h: i64, *prop_ptr: ptr, prop_len: i64, *val_ptr: ptr, val_len: i64) -> void",
            "@extern sax_event_target() -> i64",
            "@extern sax_event_target_value(*buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_event_target_checked() -> i1",
            "@extern sax_event_target_name(*buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_event_target_id(*buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_event_key(*buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_event_code(*buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_event_repeat() -> i1",
            "@extern sax_event_type(*buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_event_data(*buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_event_input_type(*buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_event_time_stamp() -> i64",
            "@extern sax_event_current_target() -> i64",
            "@extern sax_event_current_target_value(*buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_event_current_target_checked() -> i1",
            "@extern sax_event_current_target_name(*buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_event_current_target_id(*buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_event_related_target() -> i64",
            "@extern sax_event_related_target_name(*buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_event_related_target_id(*buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_event_default_prevented() -> i1",
            "@extern sax_event_button() -> i64",
            "@extern sax_event_client_x() -> i64",
            "@extern sax_event_client_y() -> i64",
            "@extern sax_event_page_x() -> i64",
            "@extern sax_event_page_y() -> i64",
            "@extern sax_event_screen_x() -> i64",
            "@extern sax_event_screen_y() -> i64",
            "@extern sax_event_pointer_id() -> i64",
            "@extern sax_event_pointer_type(*buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_event_is_primary() -> i1",
            "@extern sax_event_delta_x() -> i64",
            "@extern sax_event_delta_y() -> i64",
            "@extern sax_event_delta_z() -> i64",
            "@extern sax_event_delta_mode() -> i64",
            "@extern sax_event_touches_len() -> i64",
            "@extern sax_event_touch_identifier() -> i64",
            "@extern sax_event_touch_client_x() -> i64",
            "@extern sax_event_touch_client_y() -> i64",
            "@extern sax_event_clipboard_text(*buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_event_data_transfer_text(*buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_event_shift_key() -> i1",
            "@extern sax_event_ctrl_key() -> i1",
            "@extern sax_event_alt_key() -> i1",
            "@extern sax_event_meta_key() -> i1",
            "@extern sax_event_prevent_default() -> void",
            "@extern sax_event_stop_propagation() -> void",
            "@extern sax_dom_bind_event(node_h: i64, *evt_ptr: ptr, evt_len: i64, *handler_ptr: ptr, handler_len: i64, ctx: ptr) -> void",
            "@extern sax_dom_bind_event_capture(node_h: i64, *evt_ptr: ptr, evt_len: i64, *handler_ptr: ptr, handler_len: i64, ctx: ptr) -> void",
            "@extern sax_dom_unbind_event(node_h: i64, *evt_ptr: ptr, evt_len: i64, *handler_ptr: ptr, handler_len: i64, ctx: ptr) -> void",
            "@extern sax_set_timeout(*handler_ptr: ptr, handler_len: i64, delay_ms: i64) -> i64",
            "@extern sax_set_interval(*handler_ptr: ptr, handler_len: i64, delay_ms: i64) -> i64",
            "@extern sax_clear_timeout(id: i64) -> void",
            "@extern sax_clear_interval(id: i64) -> void",
            "@extern sax_router_get_path(*buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_router_push(*path_ptr: ptr, path_len: i64) -> void",
            "@extern sax_router_replace(*path_ptr: ptr, path_len: i64) -> void",
            "@extern sax_router_init(*path_ptr: ptr, path_len: i64) -> void",
            "@extern sax_http_get(*url_ptr: ptr, url_len: i64) -> i64",
            "@extern sax_http_post(*url_ptr: ptr, url_len: i64, *body_ptr: ptr, body_len: i64) -> i64",
            "@extern sax_get_time() -> i64",
            "@extern sax_itoa(value: i64, *buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_ftoa_bits(value_bits: i64, decimals: i64, *buf_ptr: ptr, buf_len: i64) -> i64",
            "@extern sax_json_write_string(*src_ptr: ptr, src_len: i64, *dst_ptr: ptr, dst_len: i64) -> i64",
            "@extern sax_json_write_object_members(*src_ptr: ptr, src_len: i64, *dst_ptr: ptr, dst_len: i64, prefix_comma: i1) -> i64",
            "@extern sax_json_normalize_object(*src_ptr: ptr, src_len: i64, *dst_ptr: ptr, dst_len: i64) -> i64",
            "@extern sax_mem_copy(*dst_ptr: ptr, *src_ptr: ptr, len: i64) -> void",
            "@extern sax_mem_eq(*lhs_ptr: ptr, *rhs_ptr: ptr, len: i64) -> i1",
            "@extern sax_array_push(^vec: ptr, &elem_ptr: ptr, elem_size: u64) -> ^ptr",
            "@extern sax_array_get(&vec: ptr, index: u64) -> u64",
            "@extern sax_array_remove(&vec: ptr, index: u64) -> void",
            "@extern sax_array_len(&vec: ptr) -> u64",
            "@extern sax_array_free(^vec: ptr) -> void",
        };
        for (decls) |decl| try out.writer().print("{s}\n", .{decl});
        try out.writer().writeByte('\n');
    }

    fn appendComponentForwardDecls(self: *const SaxLowerer, out: *std.ArrayList(u8)) !void {
        for (self.program_components) |component| {
            const stem = try self.componentExportStem(component.name);
            defer self.allocator.free(stem);
            try out.writer().print("@extern sax_{s}_init() -> ptr\n", .{stem});
            try out.writer().print("@extern sax_{s}_mount(parent_h: i64) -> ptr\n", .{stem});
            try out.writer().print("@extern sax_{s}_slot(ctx: ptr) -> i64\n", .{stem});
            try out.writer().print("@extern sax_{s}_root(ctx: ptr) -> i64\n", .{stem});
            try out.writer().print("@extern sax_{s}_render(ctx: ptr) -> void\n", .{stem});
            try out.writer().print("@extern sax_{s}_destroy(ctx: ptr) -> void\n", .{stem});
            for (component.state_vars) |sv| {
                switch (sv.ty) {
                    .ptr => {
                        const string_setter_name = try self.componentStringStateSetterName(component.name, sv.name);
                        defer self.allocator.free(string_setter_name);
                        try out.writer().print("@extern {s}(ctx: ptr, *value: ptr, value_len: i64) -> void\n", .{string_setter_name});
                    },
                    else => {
                        const setter_name = try self.componentStateSetterName(component.name, sv.name);
                        defer self.allocator.free(setter_name);
                        try out.writer().print("@extern {s}(ctx: ptr, value: {s}) -> void\n", .{ setter_name, stateTypeName(sv.ty) });
                    },
                }
            }
        }
        if (self.program_components.len != 0) try out.writer().writeByte('\n');
    }

    fn appendStdImports(_: *const SaxLowerer, out: *std.ArrayList(u8)) !void {
        try out.writer().writeAll("@import \"sa_std/vec.sa\"\n\n");
    }

    fn appendArrayAdapter(_: *const SaxLowerer, out: *std.ArrayList(u8)) !void {
        try out.writer().writeAll(
            \\// SAX array adapter built on top of sa_std/vec
            \\@export sax_array_push(^vec: ptr, &elem_ptr: ptr, elem_size: u64) -> ^ptr:
            \\L_ENTRY:
            \\    vec = call @sa_vec_push(^vec, elem_ptr, elem_size)
            \\    return vec
            \\
            \\@export sax_array_get(&vec: ptr, index: u64) -> u64:
            \\L_ENTRY:
            \\    len = load vec+Vec_len as u64
            \\    in_range = ult index, len
            \\    br in_range -> L_GET_HIT, L_GET_MISS
            \\L_GET_HIT:
            \\    vec_ptr = load vec+Vec_ptr as ptr
            \\    elem_off = mul index, 8
            \\    elem_ptr = ptr_add vec_ptr, elem_off
            \\    value = load elem_ptr+0 as u64
            \\    !elem_ptr
            \\    !elem_off
            \\    !vec_ptr
            \\    !len
            \\    !in_range
            \\    !vec
            \\    return value
            \\L_GET_MISS:
            \\    !len
            \\    !in_range
            \\    !vec
            \\    return 0
            \\
            \\@export sax_array_remove(&vec: ptr, index: u64) -> void:
            \\L_ENTRY:
            \\    len = load vec+Vec_len as u64
            \\    in_range = ult index, len
            \\    br in_range -> L_REMOVE, L_DONE
            \\L_REMOVE:
            \\    next_len = sub len, 1
            \\    store vec+Vec_len, next_len as u64
            \\    !next_len
            \\    !len
            \\    !in_range
            \\    !vec
            \\    return
            \\L_DONE:
            \\    !len
            \\    !in_range
            \\    !vec
            \\    return
            \\
            \\@export sax_array_len(&vec: ptr) -> u64:
            \\L_ENTRY:
            \\    len = load vec+Vec_len as u64
            \\    !vec
            \\    return len
            \\
            \\@export sax_array_free(^vec: ptr) -> void:
            \\L_ENTRY:
            \\    call @sa_vec_free(^vec)
            \\    return
            \\
        );
    }

    fn emitLoadState(self: *const SaxLowerer, out: *std.ArrayList(u8), dest: []const u8, name: []const u8) !void {
        const idx = self.stateVarIndex(name) orelse return LowerError.UnknownStateVar;
        const slot_name = try self.stateSlotConstName(name);
        defer self.allocator.free(slot_name);
        const load_ty = if (self.component.state_vars[idx].ty == .f64) "i64" else stateTypeName(self.component.state_vars[idx].ty);
        try out.writer().print("  {s} = load state+{s} as {s}\n", .{ dest, slot_name, load_ty });
    }

    fn emitInterpolationExpr(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        expr: parser.Expr,
        prefix: []const u8,
        scratch_allocator: Allocator,
    ) !InterpolationValue {
        if (std.mem.indexOfAny(u8, expr.expr, "^!") != null) return LowerError.InvalidInterpolation;
        var emitter = InterpolationExprLowerer{
            .owner = self,
            .out = out,
            .expr = expr.expr,
            .prefix = prefix,
            .scratch_allocator = scratch_allocator,
        };
        return try emitter.lower();
    }

    fn emitFormatInterpolationValue(
        _: *SaxLowerer,
        out: *std.ArrayList(u8),
        value: InterpolationValue,
        tmp_buf_name: []const u8,
        tmp_len_name: []const u8,
    ) !void {
        switch (value.ty) {
            .i64 => try out.writer().print("  {s} = call @sax_itoa({s}, *{s}, 64)\n", .{ tmp_len_name, value.name, tmp_buf_name }),
            .f64 => try out.writer().print("  {s} = call @sax_ftoa_bits({s}, 6, *{s}, 64)\n", .{ tmp_len_name, value.name, tmp_buf_name }),
            .i1, .i32, .ptr => return LowerError.InvalidTextExpression,
        }
    }

    fn emitJsonBoolLiteralCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        value_name: []const u8,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) !void {
        const true_idx = try self.string_pool.add("true");
        const false_idx = try self.string_pool.add("false");
        const true_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, true_idx });
        defer self.allocator.free(true_const);
        const false_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, false_idx });
        defer self.allocator.free(false_const);
        const label_prefix = try self.allocLabelPrefix(prefix);
        defer self.allocator.free(label_prefix);
        const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_bool_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(dst_name);
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
        try out.writer().print("  br {s} -> L_{s}_{d}_BOOL_TRUE, L_{s}_{d}_BOOL_FALSE\n", .{ value_name, label_prefix, idx, label_prefix, idx });
        try out.writer().print("L_{s}_{d}_BOOL_TRUE:\n", .{ label_prefix, idx });
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, 4)\n", .{ dst_name, true_const });
        try out.writer().print("  {s} = add {s}, 4\n", .{ len_name, len_name });
        try out.writer().print("  jmp L_{s}_{d}_BOOL_DONE\n", .{ label_prefix, idx });
        try out.writer().print("L_{s}_{d}_BOOL_FALSE:\n", .{ label_prefix, idx });
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, 5)\n", .{ dst_name, false_const });
        try out.writer().print("  {s} = add {s}, 5\n", .{ len_name, len_name });
        try out.writer().print("L_{s}_{d}_BOOL_DONE:\n", .{ label_prefix, idx });
    }

    fn emitJsonEscapedStringCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        source_state_name: []const u8,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) !void {
        const slice_prefix = try std.fmt.allocPrint(self.allocator, "{s}_json_str_{d}", .{ prefix, idx });
        defer self.allocator.free(slice_prefix);
        const slice = try self.emitLoadStateStringSlice(out, source_state_name, slice_prefix);
        defer self.allocator.free(slice.ptr_name);
        defer self.allocator.free(slice.len_name);

        const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(dst_name);
        const cap_twice_name = try std.fmt.allocPrint(self.allocator, "{s}_json_cap_twice_{d}", .{ prefix, idx });
        defer self.allocator.free(cap_twice_name);
        const cap_name = try std.fmt.allocPrint(self.allocator, "{s}_json_cap_{d}", .{ prefix, idx });
        defer self.allocator.free(cap_name);
        const written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_written_{d}", .{ prefix, idx });
        defer self.allocator.free(written_name);

        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
        try out.writer().print("  {s} = add {s}, {s}\n", .{ cap_twice_name, slice.len_name, slice.len_name });
        try out.writer().print("  {s} = add {s}, 2\n", .{ cap_name, cap_twice_name });
        try out.writer().print("  {s} = call @sax_json_write_string(*{s}, {s}, *{s}, {s})\n", .{ written_name, slice.ptr_name, slice.len_name, dst_name, cap_name });
        try out.writer().print("  {s} = add {s}, {s}\n", .{ len_name, len_name, written_name });
    }

    fn freeJsonStringValueTernary(self: *SaxLowerer, ternary: JsonStringValueTernary) void {
        switch (ternary.true_branch) {
            .state => {},
            .static_json => |json| self.allocator.free(json),
        }
        switch (ternary.false_branch) {
            .state => {},
            .static_json => |json| self.allocator.free(json),
        }
    }

    fn emitJsonStringValueBranchCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        branch: JsonStringValueBranch,
        buf_name: []const u8,
        len_name: []const u8,
        dst_name: []const u8,
        cap_name: []const u8,
        written_name: []const u8,
        branch_prefix: []const u8,
        idx: usize,
    ) !void {
        switch (branch) {
            .state => |state_name| {
                const slice_prefix = try std.fmt.allocPrint(self.allocator, "{s}_json_value_branch_{d}", .{ branch_prefix, idx });
                defer self.allocator.free(slice_prefix);
                const slice = try self.emitLoadStateStringSlice(out, state_name, slice_prefix);
                defer self.allocator.free(slice.ptr_name);
                defer self.allocator.free(slice.len_name);
                try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
                try out.writer().print("  {s} = add {s}, {s}\n", .{ cap_name, slice.len_name, slice.len_name });
                try out.writer().print("  {s} = add {s}, 2\n", .{ cap_name, cap_name });
                try out.writer().print("  {s} = call @sax_json_write_string(*{s}, {s}, *{s}, {s})\n", .{ written_name, slice.ptr_name, slice.len_name, dst_name, cap_name });
            },
            .static_json => |json| {
                const value_idx = try self.string_pool.add(json);
                const value_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, value_idx });
                defer self.allocator.free(value_const);
                try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
                try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, {})\n", .{ dst_name, value_const, self.string_pool.items.items[value_idx].len });
                try out.writer().print("  {s} = {}\n", .{ written_name, self.string_pool.items.items[value_idx].len });
            },
        }
    }

    fn emitJsonStringValueTernaryCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        ternary: JsonStringValueTernary,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) !void {
        const label_prefix = try self.allocLabelPrefix(prefix);
        defer self.allocator.free(label_prefix);
        const slot_name = try self.stateSlotConstName(ternary.condition_name);
        defer self.allocator.free(slot_name);
        const cond_name = try std.fmt.allocPrint(self.allocator, "{s}_json_value_ternary_cond_{d}", .{ prefix, idx });
        defer self.allocator.free(cond_name);
        const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_value_ternary_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(dst_name);
        const true_cap_name = try std.fmt.allocPrint(self.allocator, "{s}_json_value_ternary_true_cap_{d}", .{ prefix, idx });
        defer self.allocator.free(true_cap_name);
        const false_cap_name = try std.fmt.allocPrint(self.allocator, "{s}_json_value_ternary_false_cap_{d}", .{ prefix, idx });
        defer self.allocator.free(false_cap_name);
        const true_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_value_ternary_true_written_{d}", .{ prefix, idx });
        defer self.allocator.free(true_written_name);
        const false_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_value_ternary_false_written_{d}", .{ prefix, idx });
        defer self.allocator.free(false_written_name);
        const written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_value_ternary_written_{d}", .{ prefix, idx });
        defer self.allocator.free(written_name);

        try out.writer().print("  {s} = 0\n", .{written_name});
        try out.writer().print("  {s} = load state+{s} as i1\n", .{ cond_name, slot_name });
        try out.writer().print("  br {s} -> L_{s}_{d}_VALUE_TERNARY_TRUE, L_{s}_{d}_VALUE_TERNARY_FALSE\n", .{ cond_name, label_prefix, idx, label_prefix, idx });
        try out.writer().print("L_{s}_{d}_VALUE_TERNARY_TRUE:\n", .{ label_prefix, idx });
        try self.emitJsonStringValueBranchCopy(out, ternary.true_branch, buf_name, len_name, dst_name, true_cap_name, true_written_name, true_written_name, idx);
        try out.writer().print("  {s} = {s}\n", .{ written_name, true_written_name });
        try out.writer().print("  jmp L_{s}_{d}_VALUE_TERNARY_DONE\n", .{ label_prefix, idx });
        try out.writer().print("L_{s}_{d}_VALUE_TERNARY_FALSE:\n", .{ label_prefix, idx });
        try self.emitJsonStringValueBranchCopy(out, ternary.false_branch, buf_name, len_name, dst_name, false_cap_name, false_written_name, false_written_name, idx);
        try out.writer().print("  {s} = {s}\n", .{ written_name, false_written_name });
        try out.writer().print("L_{s}_{d}_VALUE_TERNARY_DONE:\n", .{ label_prefix, idx });
        try out.writer().print("  {s} = add {s}, {s}\n", .{ len_name, len_name, written_name });
    }

    fn emitJsonI64ValueTernaryCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        ternary: JsonI64ValueTernary,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) !void {
        const label_prefix = try self.allocLabelPrefix(prefix);
        defer self.allocator.free(label_prefix);
        const cond_slot = try self.stateSlotConstName(ternary.condition_name);
        defer self.allocator.free(cond_slot);
        const cond_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i64_ternary_cond_{d}", .{ prefix, idx });
        defer self.allocator.free(cond_name);
        const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i64_ternary_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(dst_name);
        const true_value_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i64_ternary_true_value_{d}", .{ prefix, idx });
        defer self.allocator.free(true_value_name);
        const false_value_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i64_ternary_false_value_{d}", .{ prefix, idx });
        defer self.allocator.free(false_value_name);
        const true_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i64_ternary_true_written_{d}", .{ prefix, idx });
        defer self.allocator.free(true_written_name);
        const false_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i64_ternary_false_written_{d}", .{ prefix, idx });
        defer self.allocator.free(false_written_name);
        const written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i64_ternary_written_{d}", .{ prefix, idx });
        defer self.allocator.free(written_name);

        try out.writer().print("  {s} = 0\n", .{written_name});
        try out.writer().print("  {s} = load state+{s} as i1\n", .{ cond_name, cond_slot });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
        try out.writer().print("  br {s} -> L_{s}_{d}_I64_TERNARY_TRUE, L_{s}_{d}_I64_TERNARY_FALSE\n", .{ cond_name, label_prefix, idx, label_prefix, idx });
        try out.writer().print("L_{s}_{d}_I64_TERNARY_TRUE:\n", .{ label_prefix, idx });
        try self.emitJsonI64ValueBranch(out, ternary.true_branch, true_value_name);
        try out.writer().print("  {s} = call @sax_itoa({s}, *{s}, 64)\n", .{ true_written_name, true_value_name, dst_name });
        try out.writer().print("  {s} = {s}\n", .{ written_name, true_written_name });
        try out.writer().print("  jmp L_{s}_{d}_I64_TERNARY_DONE\n", .{ label_prefix, idx });
        try out.writer().print("L_{s}_{d}_I64_TERNARY_FALSE:\n", .{ label_prefix, idx });
        try self.emitJsonI64ValueBranch(out, ternary.false_branch, false_value_name);
        try out.writer().print("  {s} = call @sax_itoa({s}, *{s}, 64)\n", .{ false_written_name, false_value_name, dst_name });
        try out.writer().print("  {s} = {s}\n", .{ written_name, false_written_name });
        try out.writer().print("L_{s}_{d}_I64_TERNARY_DONE:\n", .{ label_prefix, idx });
        try out.writer().print("  {s} = add {s}, {s}\n", .{ len_name, len_name, written_name });
    }

    fn emitJsonI64ValueBranch(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        branch: JsonI64ValueBranch,
        value_name: []const u8,
    ) !void {
        switch (branch) {
            .state => |state_name| {
                const slot = try self.stateSlotConstName(state_name);
                defer self.allocator.free(slot);
                try out.writer().print("  {s} = load state+{s} as i64\n", .{ value_name, slot });
            },
            .literal => |literal| {
                try out.writer().print("  {s} = {s}\n", .{ value_name, literal });
            },
        }
    }

    fn emitJsonI32ValueTernaryCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        ternary: JsonI32ValueTernary,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) !void {
        const label_prefix = try self.allocLabelPrefix(prefix);
        defer self.allocator.free(label_prefix);
        const cond_slot = try self.stateSlotConstName(ternary.condition_name);
        defer self.allocator.free(cond_slot);
        const cond_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i32_ternary_cond_{d}", .{ prefix, idx });
        defer self.allocator.free(cond_name);
        const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i32_ternary_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(dst_name);
        const true_raw_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i32_ternary_true_raw_{d}", .{ prefix, idx });
        defer self.allocator.free(true_raw_name);
        const false_raw_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i32_ternary_false_raw_{d}", .{ prefix, idx });
        defer self.allocator.free(false_raw_name);
        const true_value_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i32_ternary_true_value_{d}", .{ prefix, idx });
        defer self.allocator.free(true_value_name);
        const false_value_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i32_ternary_false_value_{d}", .{ prefix, idx });
        defer self.allocator.free(false_value_name);
        const true_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i32_ternary_true_written_{d}", .{ prefix, idx });
        defer self.allocator.free(true_written_name);
        const false_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i32_ternary_false_written_{d}", .{ prefix, idx });
        defer self.allocator.free(false_written_name);
        const written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i32_ternary_written_{d}", .{ prefix, idx });
        defer self.allocator.free(written_name);

        try out.writer().print("  {s} = 0\n", .{written_name});
        try out.writer().print("  {s} = load state+{s} as i1\n", .{ cond_name, cond_slot });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
        try out.writer().print("  br {s} -> L_{s}_{d}_I32_TERNARY_TRUE, L_{s}_{d}_I32_TERNARY_FALSE\n", .{ cond_name, label_prefix, idx, label_prefix, idx });
        try out.writer().print("L_{s}_{d}_I32_TERNARY_TRUE:\n", .{ label_prefix, idx });
        try self.emitJsonI32ValueBranch(out, ternary.true_branch, true_raw_name);
        try out.writer().print("  {s} = sext {s} as i64\n", .{ true_value_name, true_raw_name });
        try out.writer().print("  {s} = call @sax_itoa({s}, *{s}, 64)\n", .{ true_written_name, true_value_name, dst_name });
        try out.writer().print("  {s} = {s}\n", .{ written_name, true_written_name });
        try out.writer().print("  jmp L_{s}_{d}_I32_TERNARY_DONE\n", .{ label_prefix, idx });
        try out.writer().print("L_{s}_{d}_I32_TERNARY_FALSE:\n", .{ label_prefix, idx });
        try self.emitJsonI32ValueBranch(out, ternary.false_branch, false_raw_name);
        try out.writer().print("  {s} = sext {s} as i64\n", .{ false_value_name, false_raw_name });
        try out.writer().print("  {s} = call @sax_itoa({s}, *{s}, 64)\n", .{ false_written_name, false_value_name, dst_name });
        try out.writer().print("  {s} = {s}\n", .{ written_name, false_written_name });
        try out.writer().print("L_{s}_{d}_I32_TERNARY_DONE:\n", .{ label_prefix, idx });
        try out.writer().print("  {s} = add {s}, {s}\n", .{ len_name, len_name, written_name });
    }

    fn emitJsonI32ValueBranch(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        branch: JsonI32ValueBranch,
        raw_name: []const u8,
    ) !void {
        switch (branch) {
            .state => |state_name| {
                const slot = try self.stateSlotConstName(state_name);
                defer self.allocator.free(slot);
                try out.writer().print("  {s} = load state+{s} as i32\n", .{ raw_name, slot });
            },
            .literal => |literal| {
                try out.writer().print("  {s} = {d}\n", .{ raw_name, literal });
            },
        }
    }

    fn emitJsonF64ValueTernaryCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        ternary: JsonF64ValueTernary,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) !void {
        const label_prefix = try self.allocLabelPrefix(prefix);
        defer self.allocator.free(label_prefix);
        const cond_slot = try self.stateSlotConstName(ternary.condition_name);
        defer self.allocator.free(cond_slot);
        const cond_name = try std.fmt.allocPrint(self.allocator, "{s}_json_f64_ternary_cond_{d}", .{ prefix, idx });
        defer self.allocator.free(cond_name);
        const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_f64_ternary_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(dst_name);
        const true_value_name = try std.fmt.allocPrint(self.allocator, "{s}_json_f64_ternary_true_value_{d}", .{ prefix, idx });
        defer self.allocator.free(true_value_name);
        const false_value_name = try std.fmt.allocPrint(self.allocator, "{s}_json_f64_ternary_false_value_{d}", .{ prefix, idx });
        defer self.allocator.free(false_value_name);
        const true_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_f64_ternary_true_written_{d}", .{ prefix, idx });
        defer self.allocator.free(true_written_name);
        const false_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_f64_ternary_false_written_{d}", .{ prefix, idx });
        defer self.allocator.free(false_written_name);
        const written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_f64_ternary_written_{d}", .{ prefix, idx });
        defer self.allocator.free(written_name);

        try out.writer().print("  {s} = 0\n", .{written_name});
        try out.writer().print("  {s} = load state+{s} as i1\n", .{ cond_name, cond_slot });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
        try out.writer().print("  br {s} -> L_{s}_{d}_F64_TERNARY_TRUE, L_{s}_{d}_F64_TERNARY_FALSE\n", .{ cond_name, label_prefix, idx, label_prefix, idx });
        try out.writer().print("L_{s}_{d}_F64_TERNARY_TRUE:\n", .{ label_prefix, idx });
        try self.emitJsonF64ValueBranch(out, ternary.true_branch, true_value_name);
        try out.writer().print("  {s} = call @sax_ftoa_bits({s}, 6, *{s}, 64)\n", .{ true_written_name, true_value_name, dst_name });
        try out.writer().print("  {s} = {s}\n", .{ written_name, true_written_name });
        try out.writer().print("  jmp L_{s}_{d}_F64_TERNARY_DONE\n", .{ label_prefix, idx });
        try out.writer().print("L_{s}_{d}_F64_TERNARY_FALSE:\n", .{ label_prefix, idx });
        try self.emitJsonF64ValueBranch(out, ternary.false_branch, false_value_name);
        try out.writer().print("  {s} = call @sax_ftoa_bits({s}, 6, *{s}, 64)\n", .{ false_written_name, false_value_name, dst_name });
        try out.writer().print("  {s} = {s}\n", .{ written_name, false_written_name });
        try out.writer().print("L_{s}_{d}_F64_TERNARY_DONE:\n", .{ label_prefix, idx });
        try out.writer().print("  {s} = add {s}, {s}\n", .{ len_name, len_name, written_name });
    }

    fn emitJsonF64ValueBranch(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        branch: JsonF64ValueBranch,
        value_name: []const u8,
    ) !void {
        switch (branch) {
            .state => |state_name| {
                const slot = try self.stateSlotConstName(state_name);
                defer self.allocator.free(slot);
                try out.writer().print("  {s} = load state+{s} as i64\n", .{ value_name, slot });
            },
            .literal_bits => |bits| {
                try out.writer().print("  {s} = {d}\n", .{ value_name, bits });
            },
        }
    }

    fn emitJsonI1ValueTernaryCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        ternary: JsonI1ValueTernary,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) !void {
        const label_prefix = try self.allocLabelPrefix(prefix);
        defer self.allocator.free(label_prefix);
        const cond_slot = try self.stateSlotConstName(ternary.condition_name);
        defer self.allocator.free(cond_slot);
        const cond_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i1_ternary_cond_{d}", .{ prefix, idx });
        defer self.allocator.free(cond_name);
        const true_value_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i1_ternary_true_value_{d}", .{ prefix, idx });
        defer self.allocator.free(true_value_name);
        const false_value_name = try std.fmt.allocPrint(self.allocator, "{s}_json_i1_ternary_false_value_{d}", .{ prefix, idx });
        defer self.allocator.free(false_value_name);
        const true_prefix = try std.fmt.allocPrint(self.allocator, "{s}_json_i1_ternary_true", .{prefix});
        defer self.allocator.free(true_prefix);
        const false_prefix = try std.fmt.allocPrint(self.allocator, "{s}_json_i1_ternary_false", .{prefix});
        defer self.allocator.free(false_prefix);

        try out.writer().print("  {s} = load state+{s} as i1\n", .{ cond_name, cond_slot });
        try out.writer().print("  br {s} -> L_{s}_{d}_I1_TERNARY_TRUE, L_{s}_{d}_I1_TERNARY_FALSE\n", .{ cond_name, label_prefix, idx, label_prefix, idx });
        try out.writer().print("L_{s}_{d}_I1_TERNARY_TRUE:\n", .{ label_prefix, idx });
        try self.emitJsonI1ValueBranch(out, ternary.true_branch, true_value_name);
        try self.emitJsonBoolLiteralCopy(out, true_value_name, buf_name, len_name, true_prefix, idx);
        try out.writer().print("  jmp L_{s}_{d}_I1_TERNARY_DONE\n", .{ label_prefix, idx });
        try out.writer().print("L_{s}_{d}_I1_TERNARY_FALSE:\n", .{ label_prefix, idx });
        try self.emitJsonI1ValueBranch(out, ternary.false_branch, false_value_name);
        try self.emitJsonBoolLiteralCopy(out, false_value_name, buf_name, len_name, false_prefix, idx);
        try out.writer().print("L_{s}_{d}_I1_TERNARY_DONE:\n", .{ label_prefix, idx });
    }

    fn emitJsonI1ValueBranch(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        branch: JsonI1ValueBranch,
        value_name: []const u8,
    ) !void {
        switch (branch) {
            .state => |state_name| {
                const slot = try self.stateSlotConstName(state_name);
                defer self.allocator.free(slot);
                try out.writer().print("  {s} = load state+{s} as i1\n", .{ value_name, slot });
            },
            .literal => |literal| {
                try out.writer().print("  {s} = {d} as i1\n", .{ value_name, @intFromBool(literal) });
            },
        }
    }

    fn emitJsonI64TernaryKeyCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        ternary: JsonI64TernaryKey,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) !void {
        const label_prefix = try self.allocLabelPrefix(prefix);
        defer self.allocator.free(label_prefix);
        const cond_slot = try self.stateSlotConstName(ternary.condition_name);
        defer self.allocator.free(cond_slot);
        const quote_idx = try self.string_pool.add("\"");
        const quote_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, quote_idx });
        defer self.allocator.free(quote_const);
        const cond_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i64_ternary_cond_{d}", .{ prefix, idx });
        defer self.allocator.free(cond_name);
        const open_dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i64_ternary_open_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(open_dst_name);
        const value_dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i64_ternary_value_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(value_dst_name);
        const close_dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i64_ternary_close_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(close_dst_name);
        const true_value_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i64_ternary_true_value_{d}", .{ prefix, idx });
        defer self.allocator.free(true_value_name);
        const false_value_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i64_ternary_false_value_{d}", .{ prefix, idx });
        defer self.allocator.free(false_value_name);
        const true_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i64_ternary_true_written_{d}", .{ prefix, idx });
        defer self.allocator.free(true_written_name);
        const false_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i64_ternary_false_written_{d}", .{ prefix, idx });
        defer self.allocator.free(false_written_name);
        const written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i64_ternary_written_{d}", .{ prefix, idx });
        defer self.allocator.free(written_name);

        try out.writer().print("  {s} = 0\n", .{written_name});
        try out.writer().print("  {s} = load state+{s} as i1\n", .{ cond_name, cond_slot });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ open_dst_name, buf_name, len_name });
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, 1)\n", .{ open_dst_name, quote_const });
        try out.writer().print("  {s} = add {s}, 1\n", .{ len_name, len_name });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ value_dst_name, buf_name, len_name });
        try out.writer().print("  br {s} -> L_{s}_{d}_KEY_I64_TERNARY_TRUE, L_{s}_{d}_KEY_I64_TERNARY_FALSE\n", .{ cond_name, label_prefix, idx, label_prefix, idx });
        try out.writer().print("L_{s}_{d}_KEY_I64_TERNARY_TRUE:\n", .{ label_prefix, idx });
        try self.emitJsonI64ValueBranch(out, ternary.true_branch, true_value_name);
        try out.writer().print("  {s} = call @sax_itoa({s}, *{s}, 64)\n", .{ true_written_name, true_value_name, value_dst_name });
        try out.writer().print("  {s} = {s}\n", .{ written_name, true_written_name });
        try out.writer().print("  jmp L_{s}_{d}_KEY_I64_TERNARY_DONE\n", .{ label_prefix, idx });
        try out.writer().print("L_{s}_{d}_KEY_I64_TERNARY_FALSE:\n", .{ label_prefix, idx });
        try self.emitJsonI64ValueBranch(out, ternary.false_branch, false_value_name);
        try out.writer().print("  {s} = call @sax_itoa({s}, *{s}, 64)\n", .{ false_written_name, false_value_name, value_dst_name });
        try out.writer().print("  {s} = {s}\n", .{ written_name, false_written_name });
        try out.writer().print("L_{s}_{d}_KEY_I64_TERNARY_DONE:\n", .{ label_prefix, idx });
        try out.writer().print("  {s} = add {s}, {s}\n", .{ len_name, len_name, written_name });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ close_dst_name, buf_name, len_name });
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, 1)\n", .{ close_dst_name, quote_const });
        try out.writer().print("  {s} = add {s}, 1\n", .{ len_name, len_name });
    }

    fn emitJsonQuotedBoolKeyCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        value_name: []const u8,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) !void {
        const true_idx = try self.string_pool.add("\"true\"");
        const false_idx = try self.string_pool.add("\"false\"");
        const true_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, true_idx });
        defer self.allocator.free(true_const);
        const false_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, false_idx });
        defer self.allocator.free(false_const);
        const label_prefix = try self.allocLabelPrefix(prefix);
        defer self.allocator.free(label_prefix);
        const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_bool_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(dst_name);
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
        try out.writer().print("  br {s} -> L_{s}_{d}_KEY_BOOL_TRUE, L_{s}_{d}_KEY_BOOL_FALSE\n", .{ value_name, label_prefix, idx, label_prefix, idx });
        try out.writer().print("L_{s}_{d}_KEY_BOOL_TRUE:\n", .{ label_prefix, idx });
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, 6)\n", .{ dst_name, true_const });
        try out.writer().print("  {s} = add {s}, 6\n", .{ len_name, len_name });
        try out.writer().print("  jmp L_{s}_{d}_KEY_BOOL_DONE\n", .{ label_prefix, idx });
        try out.writer().print("L_{s}_{d}_KEY_BOOL_FALSE:\n", .{ label_prefix, idx });
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, 7)\n", .{ dst_name, false_const });
        try out.writer().print("  {s} = add {s}, 7\n", .{ len_name, len_name });
        try out.writer().print("L_{s}_{d}_KEY_BOOL_DONE:\n", .{ label_prefix, idx });
    }

    fn emitJsonI32TernaryKeyCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        ternary: JsonI32TernaryKey,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) !void {
        const label_prefix = try self.allocLabelPrefix(prefix);
        defer self.allocator.free(label_prefix);
        const cond_slot = try self.stateSlotConstName(ternary.condition_name);
        defer self.allocator.free(cond_slot);
        const quote_idx = try self.string_pool.add("\"");
        const quote_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, quote_idx });
        defer self.allocator.free(quote_const);
        const cond_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i32_ternary_cond_{d}", .{ prefix, idx });
        defer self.allocator.free(cond_name);
        const open_dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i32_ternary_open_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(open_dst_name);
        const value_dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i32_ternary_value_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(value_dst_name);
        const close_dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i32_ternary_close_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(close_dst_name);
        const true_raw_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i32_ternary_true_raw_{d}", .{ prefix, idx });
        defer self.allocator.free(true_raw_name);
        const false_raw_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i32_ternary_false_raw_{d}", .{ prefix, idx });
        defer self.allocator.free(false_raw_name);
        const true_value_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i32_ternary_true_value_{d}", .{ prefix, idx });
        defer self.allocator.free(true_value_name);
        const false_value_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i32_ternary_false_value_{d}", .{ prefix, idx });
        defer self.allocator.free(false_value_name);
        const true_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i32_ternary_true_written_{d}", .{ prefix, idx });
        defer self.allocator.free(true_written_name);
        const false_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i32_ternary_false_written_{d}", .{ prefix, idx });
        defer self.allocator.free(false_written_name);
        const written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i32_ternary_written_{d}", .{ prefix, idx });
        defer self.allocator.free(written_name);

        try out.writer().print("  {s} = 0\n", .{written_name});
        try out.writer().print("  {s} = load state+{s} as i1\n", .{ cond_name, cond_slot });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ open_dst_name, buf_name, len_name });
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, 1)\n", .{ open_dst_name, quote_const });
        try out.writer().print("  {s} = add {s}, 1\n", .{ len_name, len_name });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ value_dst_name, buf_name, len_name });
        try out.writer().print("  br {s} -> L_{s}_{d}_KEY_I32_TERNARY_TRUE, L_{s}_{d}_KEY_I32_TERNARY_FALSE\n", .{ cond_name, label_prefix, idx, label_prefix, idx });
        try out.writer().print("L_{s}_{d}_KEY_I32_TERNARY_TRUE:\n", .{ label_prefix, idx });
        try self.emitJsonI32ValueBranch(out, ternary.true_branch, true_raw_name);
        try out.writer().print("  {s} = sext {s} as i64\n", .{ true_value_name, true_raw_name });
        try out.writer().print("  {s} = call @sax_itoa({s}, *{s}, 64)\n", .{ true_written_name, true_value_name, value_dst_name });
        try out.writer().print("  {s} = {s}\n", .{ written_name, true_written_name });
        try out.writer().print("  jmp L_{s}_{d}_KEY_I32_TERNARY_DONE\n", .{ label_prefix, idx });
        try out.writer().print("L_{s}_{d}_KEY_I32_TERNARY_FALSE:\n", .{ label_prefix, idx });
        try self.emitJsonI32ValueBranch(out, ternary.false_branch, false_raw_name);
        try out.writer().print("  {s} = sext {s} as i64\n", .{ false_value_name, false_raw_name });
        try out.writer().print("  {s} = call @sax_itoa({s}, *{s}, 64)\n", .{ false_written_name, false_value_name, value_dst_name });
        try out.writer().print("  {s} = {s}\n", .{ written_name, false_written_name });
        try out.writer().print("L_{s}_{d}_KEY_I32_TERNARY_DONE:\n", .{ label_prefix, idx });
        try out.writer().print("  {s} = add {s}, {s}\n", .{ len_name, len_name, written_name });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ close_dst_name, buf_name, len_name });
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, 1)\n", .{ close_dst_name, quote_const });
        try out.writer().print("  {s} = add {s}, 1\n", .{ len_name, len_name });
    }

    fn emitJsonI1TernaryKeyCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        ternary: JsonI1TernaryKey,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) !void {
        const label_prefix = try self.allocLabelPrefix(prefix);
        defer self.allocator.free(label_prefix);
        const cond_slot = try self.stateSlotConstName(ternary.condition_name);
        defer self.allocator.free(cond_slot);
        const cond_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i1_ternary_cond_{d}", .{ prefix, idx });
        defer self.allocator.free(cond_name);
        const true_value_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i1_ternary_true_value_{d}", .{ prefix, idx });
        defer self.allocator.free(true_value_name);
        const false_value_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i1_ternary_false_value_{d}", .{ prefix, idx });
        defer self.allocator.free(false_value_name);
        const true_prefix = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i1_ternary_true", .{prefix});
        defer self.allocator.free(true_prefix);
        const false_prefix = try std.fmt.allocPrint(self.allocator, "{s}_json_key_i1_ternary_false", .{prefix});
        defer self.allocator.free(false_prefix);

        try out.writer().print("  {s} = load state+{s} as i1\n", .{ cond_name, cond_slot });
        try out.writer().print("  br {s} -> L_{s}_{d}_KEY_I1_TERNARY_TRUE, L_{s}_{d}_KEY_I1_TERNARY_FALSE\n", .{ cond_name, label_prefix, idx, label_prefix, idx });
        try out.writer().print("L_{s}_{d}_KEY_I1_TERNARY_TRUE:\n", .{ label_prefix, idx });
        try self.emitJsonI1ValueBranch(out, ternary.true_branch, true_value_name);
        try self.emitJsonQuotedBoolKeyCopy(out, true_value_name, buf_name, len_name, true_prefix, idx);
        try out.writer().print("  jmp L_{s}_{d}_KEY_I1_TERNARY_DONE\n", .{ label_prefix, idx });
        try out.writer().print("L_{s}_{d}_KEY_I1_TERNARY_FALSE:\n", .{ label_prefix, idx });
        try self.emitJsonI1ValueBranch(out, ternary.false_branch, false_value_name);
        try self.emitJsonQuotedBoolKeyCopy(out, false_value_name, buf_name, len_name, false_prefix, idx);
        try out.writer().print("L_{s}_{d}_KEY_I1_TERNARY_DONE:\n", .{ label_prefix, idx });
    }

    fn emitJsonF64TernaryKeyCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        ternary: JsonF64TernaryKey,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) !void {
        const label_prefix = try self.allocLabelPrefix(prefix);
        defer self.allocator.free(label_prefix);
        const cond_slot = try self.stateSlotConstName(ternary.condition_name);
        defer self.allocator.free(cond_slot);
        const quote_idx = try self.string_pool.add("\"");
        const quote_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, quote_idx });
        defer self.allocator.free(quote_const);
        const cond_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_f64_ternary_cond_{d}", .{ prefix, idx });
        defer self.allocator.free(cond_name);
        const open_dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_f64_ternary_open_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(open_dst_name);
        const value_dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_f64_ternary_value_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(value_dst_name);
        const close_dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_f64_ternary_close_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(close_dst_name);
        const true_value_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_f64_ternary_true_value_{d}", .{ prefix, idx });
        defer self.allocator.free(true_value_name);
        const false_value_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_f64_ternary_false_value_{d}", .{ prefix, idx });
        defer self.allocator.free(false_value_name);
        const true_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_f64_ternary_true_written_{d}", .{ prefix, idx });
        defer self.allocator.free(true_written_name);
        const false_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_f64_ternary_false_written_{d}", .{ prefix, idx });
        defer self.allocator.free(false_written_name);
        const written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_f64_ternary_written_{d}", .{ prefix, idx });
        defer self.allocator.free(written_name);

        try out.writer().print("  {s} = 0\n", .{written_name});
        try out.writer().print("  {s} = load state+{s} as i1\n", .{ cond_name, cond_slot });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ open_dst_name, buf_name, len_name });
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, 1)\n", .{ open_dst_name, quote_const });
        try out.writer().print("  {s} = add {s}, 1\n", .{ len_name, len_name });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ value_dst_name, buf_name, len_name });
        try out.writer().print("  br {s} -> L_{s}_{d}_KEY_F64_TERNARY_TRUE, L_{s}_{d}_KEY_F64_TERNARY_FALSE\n", .{ cond_name, label_prefix, idx, label_prefix, idx });
        try out.writer().print("L_{s}_{d}_KEY_F64_TERNARY_TRUE:\n", .{ label_prefix, idx });
        try self.emitJsonF64ValueBranch(out, ternary.true_branch, true_value_name);
        try out.writer().print("  {s} = call @sax_ftoa_bits({s}, 6, *{s}, 64)\n", .{ true_written_name, true_value_name, value_dst_name });
        try out.writer().print("  {s} = {s}\n", .{ written_name, true_written_name });
        try out.writer().print("  jmp L_{s}_{d}_KEY_F64_TERNARY_DONE\n", .{ label_prefix, idx });
        try out.writer().print("L_{s}_{d}_KEY_F64_TERNARY_FALSE:\n", .{ label_prefix, idx });
        try self.emitJsonF64ValueBranch(out, ternary.false_branch, false_value_name);
        try out.writer().print("  {s} = call @sax_ftoa_bits({s}, 6, *{s}, 64)\n", .{ false_written_name, false_value_name, value_dst_name });
        try out.writer().print("  {s} = {s}\n", .{ written_name, false_written_name });
        try out.writer().print("L_{s}_{d}_KEY_F64_TERNARY_DONE:\n", .{ label_prefix, idx });
        try out.writer().print("  {s} = add {s}, {s}\n", .{ len_name, len_name, written_name });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ close_dst_name, buf_name, len_name });
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, 1)\n", .{ close_dst_name, quote_const });
        try out.writer().print("  {s} = add {s}, 1\n", .{ len_name, len_name });
    }

    fn emitJsonStringTernaryKeyCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        ternary: JsonStringTernaryKey,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) !void {
        const true_idx = try self.string_pool.add(ternary.true_key_json);
        const false_idx = try self.string_pool.add(ternary.false_key_json);
        const true_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, true_idx });
        defer self.allocator.free(true_const);
        const false_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, false_idx });
        defer self.allocator.free(false_const);
        const label_prefix = try self.allocLabelPrefix(prefix);
        defer self.allocator.free(label_prefix);
        const slot_name = try self.stateSlotConstName(ternary.condition_name);
        defer self.allocator.free(slot_name);
        const cond_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_ternary_cond_{d}", .{ prefix, idx });
        defer self.allocator.free(cond_name);
        const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_ternary_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(dst_name);
        const true_len = self.string_pool.items.items[true_idx].len;
        const false_len = self.string_pool.items.items[false_idx].len;

        try out.writer().print("  {s} = load state+{s} as i1\n", .{ cond_name, slot_name });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
        try out.writer().print("  br {s} -> L_{s}_{d}_KEY_TERNARY_TRUE, L_{s}_{d}_KEY_TERNARY_FALSE\n", .{ cond_name, label_prefix, idx, label_prefix, idx });
        try out.writer().print("L_{s}_{d}_KEY_TERNARY_TRUE:\n", .{ label_prefix, idx });
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, {})\n", .{ dst_name, true_const, true_len });
        try out.writer().print("  {s} = add {s}, {}\n", .{ len_name, len_name, true_len });
        try out.writer().print("  jmp L_{s}_{d}_KEY_TERNARY_DONE\n", .{ label_prefix, idx });
        try out.writer().print("L_{s}_{d}_KEY_TERNARY_FALSE:\n", .{ label_prefix, idx });
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, {})\n", .{ dst_name, false_const, false_len });
        try out.writer().print("  {s} = add {s}, {}\n", .{ len_name, len_name, false_len });
        try out.writer().print("L_{s}_{d}_KEY_TERNARY_DONE:\n", .{ label_prefix, idx });
    }

    fn emitJsonPtrStringTernaryKeyCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        ternary: JsonPtrStringTernaryKey,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) !void {
        const true_slice_prefix = try std.fmt.allocPrint(self.allocator, "{s}_json_key_ptr_true_{d}", .{ prefix, idx });
        defer self.allocator.free(true_slice_prefix);
        const true_slice = try self.emitLoadStateStringSlice(out, ternary.true_state_name, true_slice_prefix);
        defer self.allocator.free(true_slice.ptr_name);
        defer self.allocator.free(true_slice.len_name);
        const false_slice_prefix = try std.fmt.allocPrint(self.allocator, "{s}_json_key_ptr_false_{d}", .{ prefix, idx });
        defer self.allocator.free(false_slice_prefix);
        const false_slice = try self.emitLoadStateStringSlice(out, ternary.false_state_name, false_slice_prefix);
        defer self.allocator.free(false_slice.ptr_name);
        defer self.allocator.free(false_slice.len_name);

        const label_prefix = try self.allocLabelPrefix(prefix);
        defer self.allocator.free(label_prefix);
        const slot_name = try self.stateSlotConstName(ternary.condition_name);
        defer self.allocator.free(slot_name);
        const cond_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_ptr_ternary_cond_{d}", .{ prefix, idx });
        defer self.allocator.free(cond_name);
        const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_ptr_ternary_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(dst_name);
        const true_cap_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_ptr_ternary_true_cap_{d}", .{ prefix, idx });
        defer self.allocator.free(true_cap_name);
        const false_cap_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_ptr_ternary_false_cap_{d}", .{ prefix, idx });
        defer self.allocator.free(false_cap_name);
        const true_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_ptr_ternary_true_written_{d}", .{ prefix, idx });
        defer self.allocator.free(true_written_name);
        const false_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_ptr_ternary_false_written_{d}", .{ prefix, idx });
        defer self.allocator.free(false_written_name);
        const written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_ptr_ternary_written_{d}", .{ prefix, idx });
        defer self.allocator.free(written_name);

        try out.writer().print("  {s} = 0\n", .{written_name});
        try out.writer().print("  {s} = load state+{s} as i1\n", .{ cond_name, slot_name });
        try out.writer().print("  br {s} -> L_{s}_{d}_KEY_PTR_TERNARY_TRUE, L_{s}_{d}_KEY_PTR_TERNARY_FALSE\n", .{ cond_name, label_prefix, idx, label_prefix, idx });
        try out.writer().print("L_{s}_{d}_KEY_PTR_TERNARY_TRUE:\n", .{ label_prefix, idx });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
        try out.writer().print("  {s} = add {s}, {s}\n", .{ true_cap_name, true_slice.len_name, true_slice.len_name });
        try out.writer().print("  {s} = add {s}, 2\n", .{ true_cap_name, true_cap_name });
        try out.writer().print("  {s} = call @sax_json_write_string(*{s}, {s}, *{s}, {s})\n", .{ true_written_name, true_slice.ptr_name, true_slice.len_name, dst_name, true_cap_name });
        try out.writer().print("  {s} = {s}\n", .{ written_name, true_written_name });
        try out.writer().print("  jmp L_{s}_{d}_KEY_PTR_TERNARY_DONE\n", .{ label_prefix, idx });
        try out.writer().print("L_{s}_{d}_KEY_PTR_TERNARY_FALSE:\n", .{ label_prefix, idx });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
        try out.writer().print("  {s} = add {s}, {s}\n", .{ false_cap_name, false_slice.len_name, false_slice.len_name });
        try out.writer().print("  {s} = add {s}, 2\n", .{ false_cap_name, false_cap_name });
        try out.writer().print("  {s} = call @sax_json_write_string(*{s}, {s}, *{s}, {s})\n", .{ false_written_name, false_slice.ptr_name, false_slice.len_name, dst_name, false_cap_name });
        try out.writer().print("  {s} = {s}\n", .{ written_name, false_written_name });
        try out.writer().print("L_{s}_{d}_KEY_PTR_TERNARY_DONE:\n", .{ label_prefix, idx });
        try out.writer().print("  {s} = add {s}, {s}\n", .{ len_name, len_name, written_name });
    }

    fn freeJsonMixedStringTernaryKey(self: *SaxLowerer, ternary: JsonMixedStringTernaryKey) void {
        switch (ternary.true_branch) {
            .state => {},
            .static_json => |json| self.allocator.free(json),
        }
        switch (ternary.false_branch) {
            .state => {},
            .static_json => |json| self.allocator.free(json),
        }
    }

    fn emitJsonStringKeyBranchCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        branch: JsonStringKeyBranch,
        buf_name: []const u8,
        len_name: []const u8,
        dst_name: []const u8,
        cap_name: []const u8,
        written_name: []const u8,
        branch_prefix: []const u8,
        idx: usize,
    ) !void {
        switch (branch) {
            .state => |state_name| {
                const slice_prefix = try std.fmt.allocPrint(self.allocator, "{s}_json_key_branch_{d}", .{ branch_prefix, idx });
                defer self.allocator.free(slice_prefix);
                const slice = try self.emitLoadStateStringSlice(out, state_name, slice_prefix);
                defer self.allocator.free(slice.ptr_name);
                defer self.allocator.free(slice.len_name);
                try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
                try out.writer().print("  {s} = add {s}, {s}\n", .{ cap_name, slice.len_name, slice.len_name });
                try out.writer().print("  {s} = add {s}, 2\n", .{ cap_name, cap_name });
                try out.writer().print("  {s} = call @sax_json_write_string(*{s}, {s}, *{s}, {s})\n", .{ written_name, slice.ptr_name, slice.len_name, dst_name, cap_name });
            },
            .static_json => |json| {
                const value_idx = try self.string_pool.add(json);
                const value_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, value_idx });
                defer self.allocator.free(value_const);
                try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
                try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, {})\n", .{ dst_name, value_const, self.string_pool.items.items[value_idx].len });
                try out.writer().print("  {s} = {}\n", .{ written_name, self.string_pool.items.items[value_idx].len });
            },
        }
    }

    fn emitJsonMixedStringTernaryKeyCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        ternary: JsonMixedStringTernaryKey,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) !void {
        const label_prefix = try self.allocLabelPrefix(prefix);
        defer self.allocator.free(label_prefix);
        const slot_name = try self.stateSlotConstName(ternary.condition_name);
        defer self.allocator.free(slot_name);
        const cond_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_mixed_ternary_cond_{d}", .{ prefix, idx });
        defer self.allocator.free(cond_name);
        const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_mixed_ternary_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(dst_name);
        const true_cap_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_mixed_ternary_true_cap_{d}", .{ prefix, idx });
        defer self.allocator.free(true_cap_name);
        const false_cap_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_mixed_ternary_false_cap_{d}", .{ prefix, idx });
        defer self.allocator.free(false_cap_name);
        const true_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_mixed_ternary_true_written_{d}", .{ prefix, idx });
        defer self.allocator.free(true_written_name);
        const false_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_mixed_ternary_false_written_{d}", .{ prefix, idx });
        defer self.allocator.free(false_written_name);
        const written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_mixed_ternary_written_{d}", .{ prefix, idx });
        defer self.allocator.free(written_name);

        try out.writer().print("  {s} = 0\n", .{written_name});
        try out.writer().print("  {s} = load state+{s} as i1\n", .{ cond_name, slot_name });
        try out.writer().print("  br {s} -> L_{s}_{d}_KEY_MIXED_TERNARY_TRUE, L_{s}_{d}_KEY_MIXED_TERNARY_FALSE\n", .{ cond_name, label_prefix, idx, label_prefix, idx });
        try out.writer().print("L_{s}_{d}_KEY_MIXED_TERNARY_TRUE:\n", .{ label_prefix, idx });
        try self.emitJsonStringKeyBranchCopy(out, ternary.true_branch, buf_name, len_name, dst_name, true_cap_name, true_written_name, true_written_name, idx);
        try out.writer().print("  {s} = {s}\n", .{ written_name, true_written_name });
        try out.writer().print("  jmp L_{s}_{d}_KEY_MIXED_TERNARY_DONE\n", .{ label_prefix, idx });
        try out.writer().print("L_{s}_{d}_KEY_MIXED_TERNARY_FALSE:\n", .{ label_prefix, idx });
        try self.emitJsonStringKeyBranchCopy(out, ternary.false_branch, buf_name, len_name, dst_name, false_cap_name, false_written_name, false_written_name, idx);
        try out.writer().print("  {s} = {s}\n", .{ written_name, false_written_name });
        try out.writer().print("L_{s}_{d}_KEY_MIXED_TERNARY_DONE:\n", .{ label_prefix, idx });
        try out.writer().print("  {s} = add {s}, {s}\n", .{ len_name, len_name, written_name });
    }

    fn emitJsonStringInterpolationCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        expr: parser.Expr,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) !void {
        if (try self.parseJsonI64TernaryKey(expr)) |ternary| {
            try self.emitJsonI64TernaryKeyCopy(out, ternary, buf_name, len_name, prefix, idx);
            return;
        }

        if (try self.parseJsonI32TernaryKey(expr)) |ternary| {
            try self.emitJsonI32TernaryKeyCopy(out, ternary, buf_name, len_name, prefix, idx);
            return;
        }

        if (try self.parseJsonF64TernaryKey(expr)) |ternary| {
            try self.emitJsonF64TernaryKeyCopy(out, ternary, buf_name, len_name, prefix, idx);
            return;
        }

        if (try self.parseJsonI1TernaryKey(expr)) |ternary| {
            try self.emitJsonI1TernaryKeyCopy(out, ternary, buf_name, len_name, prefix, idx);
            return;
        }

        if (try self.parseJsonMixedStringTernaryKey(expr)) |ternary| {
            defer self.freeJsonMixedStringTernaryKey(ternary);
            try self.emitJsonMixedStringTernaryKeyCopy(out, ternary, buf_name, len_name, prefix, idx);
            return;
        }

        if (try self.parseJsonPtrStringTernaryKey(expr)) |ternary| {
            try self.emitJsonPtrStringTernaryKeyCopy(out, ternary, buf_name, len_name, prefix, idx);
            return;
        }

        if (try self.parseJsonStringTernaryKey(expr)) |ternary| {
            defer self.allocator.free(ternary.true_key_json);
            defer self.allocator.free(ternary.false_key_json);
            try self.emitJsonStringTernaryKeyCopy(out, ternary, buf_name, len_name, prefix, idx);
            return;
        }

        if (simpleStateExprName(expr)) |name| {
            if (self.stateVar(name)) |sv| {
                if (sv.ty == .ptr) {
                    try self.emitJsonEscapedStringCopy(out, name, buf_name, len_name, prefix, idx);
                    return;
                }
                if (sv.ty == .i1) {
                    const slot_name = try self.stateSlotConstName(name);
                    defer self.allocator.free(slot_name);
                    const bool_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_bool_{d}", .{ prefix, idx });
                    defer self.allocator.free(bool_name);
                    try out.writer().print("  {s} = load state+{s} as i1\n", .{ bool_name, slot_name });
                    try self.emitJsonQuotedBoolKeyCopy(out, bool_name, buf_name, len_name, prefix, idx);
                    return;
                }
            }
        }

        var expr_arena = std.heap.ArenaAllocator.init(self.allocator);
        defer expr_arena.deinit();
        const expr_prefix = try std.fmt.allocPrint(self.allocator, "{s}_json_key_expr_{d}", .{ prefix, idx });
        defer self.allocator.free(expr_prefix);
        const value = try self.emitInterpolationExpr(out, expr, expr_prefix, expr_arena.allocator());

        const tmp_buf_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_tmp_{d}", .{ prefix, idx });
        defer self.allocator.free(tmp_buf_name);
        const tmp_len_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_tmp_len_{d}", .{ prefix, idx });
        defer self.allocator.free(tmp_len_name);
        const quote_idx = try self.string_pool.add("\"");
        const quote_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, quote_idx });
        defer self.allocator.free(quote_const);
        const open_dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_open_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(open_dst_name);
        const value_dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_value_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(value_dst_name);
        const close_dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_key_close_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(close_dst_name);

        try out.writer().print("  {s} = stack_alloc 64\n", .{tmp_buf_name});
        try self.emitFormatInterpolationValue(out, value, tmp_buf_name, tmp_len_name);
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ open_dst_name, buf_name, len_name });
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, 1)\n", .{ open_dst_name, quote_const });
        try out.writer().print("  {s} = add {s}, 1\n", .{ len_name, len_name });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ value_dst_name, buf_name, len_name });
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, {s})\n", .{ value_dst_name, tmp_buf_name, tmp_len_name });
        try out.writer().print("  {s} = add {s}, {s}\n", .{ len_name, len_name, tmp_len_name });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ close_dst_name, buf_name, len_name });
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, 1)\n", .{ close_dst_name, quote_const });
        try out.writer().print("  {s} = add {s}, 1\n", .{ len_name, len_name });
    }

    fn emitJsonObjectSpreadCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        spread: parser.JsonObjectSpreadPiece,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) ![]const u8 {
        if (try self.parseJsonObjectSpreadTernary(spread.expr)) |ternary| {
            defer self.freeJsonObjectSpreadTernary(ternary);
            return self.emitJsonObjectSpreadTernaryCopy(out, ternary, spread.prefix_comma, buf_name, len_name, prefix, idx);
        }
        if (try self.parseJsonObjectSpreadLogicalAnd(spread.expr)) |logical_and| {
            defer self.freeJsonObjectSpreadTernary(logical_and);
            return self.emitJsonObjectSpreadTernaryCopy(out, logical_and, spread.prefix_comma, buf_name, len_name, prefix, idx);
        }
        if (try self.parseJsonObjectSpreadLogicalOr(spread.expr)) |logical_or| {
            defer self.freeJsonObjectSpreadTernary(logical_or);
            return self.emitJsonObjectSpreadTernaryCopy(out, logical_or, spread.prefix_comma, buf_name, len_name, prefix, idx);
        }

        const state_name = simpleStateExprName(spread.expr) orelse return LowerError.InvalidTextExpression;
        const slice_prefix = try std.fmt.allocPrint(self.allocator, "{s}_json_obj_{d}", .{ prefix, idx });
        defer self.allocator.free(slice_prefix);
        const slice = try self.emitLoadStateStringSlice(out, state_name, slice_prefix);
        defer self.allocator.free(slice.ptr_name);
        defer self.allocator.free(slice.len_name);

        const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_obj_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(dst_name);
        const cap_name = try std.fmt.allocPrint(self.allocator, "{s}_json_obj_cap_{d}", .{ prefix, idx });
        defer self.allocator.free(cap_name);
        const written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_obj_written_{d}", .{ prefix, idx });

        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
        try out.writer().print("  {s} = add {s}, 1\n", .{ cap_name, slice.len_name });
        const prefix_comma: i32 = if (spread.prefix_comma) 1 else 0;
        try out.writer().print("  {s} = call @sax_json_write_object_members(*{s}, {s}, *{s}, {s}, {})\n", .{ written_name, slice.ptr_name, slice.len_name, dst_name, cap_name, prefix_comma });
        try out.writer().print("  {s} = add {s}, {s}\n", .{ len_name, len_name, written_name });
        return written_name;
    }

    fn freeJsonObjectSpreadTernary(self: *SaxLowerer, ternary: JsonObjectSpreadTernary) void {
        switch (ternary.true_branch) {
            .state => {},
            .static_json => |json| self.allocator.free(json),
        }
        switch (ternary.false_branch) {
            .state => {},
            .static_json => |json| self.allocator.free(json),
        }
    }

    fn emitJsonObjectSpreadBranchSlice(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        branch: JsonObjectSpreadBranch,
        slice_prefix: []const u8,
    ) !StateStringSlice {
        return switch (branch) {
            .state => |state_name| try self.emitLoadStateStringSlice(out, state_name, slice_prefix),
            .static_json => |json| blk: {
                const idx = try self.string_pool.add(json);
                const ptr_name = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, idx });
                errdefer self.allocator.free(ptr_name);
                const len_name = try std.fmt.allocPrint(self.allocator, "{}", .{self.string_pool.items.items[idx].len});
                errdefer self.allocator.free(len_name);
                break :blk .{ .ptr_name = ptr_name, .len_name = len_name };
            },
        };
    }

    fn emitJsonObjectSpreadTernaryCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        ternary: JsonObjectSpreadTernary,
        prefix_comma_enabled: bool,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) ![]const u8 {
        const true_slice_prefix = try std.fmt.allocPrint(self.allocator, "{s}_json_obj_true_{d}", .{ prefix, idx });
        defer self.allocator.free(true_slice_prefix);
        const true_slice = try self.emitJsonObjectSpreadBranchSlice(out, ternary.true_branch, true_slice_prefix);
        defer self.allocator.free(true_slice.ptr_name);
        defer self.allocator.free(true_slice.len_name);
        const false_slice_prefix = try std.fmt.allocPrint(self.allocator, "{s}_json_obj_false_{d}", .{ prefix, idx });
        defer self.allocator.free(false_slice_prefix);
        const false_slice = try self.emitJsonObjectSpreadBranchSlice(out, ternary.false_branch, false_slice_prefix);
        defer self.allocator.free(false_slice.ptr_name);
        defer self.allocator.free(false_slice.len_name);

        const label_prefix = try self.allocLabelPrefix(prefix);
        defer self.allocator.free(label_prefix);
        const slot_name = try self.stateSlotConstName(ternary.condition_name);
        defer self.allocator.free(slot_name);
        const cond_name = try std.fmt.allocPrint(self.allocator, "{s}_json_obj_ternary_cond_{d}", .{ prefix, idx });
        defer self.allocator.free(cond_name);
        const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_json_obj_ternary_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(dst_name);
        const true_cap_name = try std.fmt.allocPrint(self.allocator, "{s}_json_obj_ternary_true_cap_{d}", .{ prefix, idx });
        defer self.allocator.free(true_cap_name);
        const false_cap_name = try std.fmt.allocPrint(self.allocator, "{s}_json_obj_ternary_false_cap_{d}", .{ prefix, idx });
        defer self.allocator.free(false_cap_name);
        const true_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_obj_ternary_true_written_{d}", .{ prefix, idx });
        defer self.allocator.free(true_written_name);
        const false_written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_obj_ternary_false_written_{d}", .{ prefix, idx });
        defer self.allocator.free(false_written_name);
        const written_name = try std.fmt.allocPrint(self.allocator, "{s}_json_obj_ternary_written_{d}", .{ prefix, idx });
        const prefix_comma: i32 = if (prefix_comma_enabled) 1 else 0;

        try out.writer().print("  {s} = 0\n", .{written_name});
        try out.writer().print("  {s} = load state+{s} as i1\n", .{ cond_name, slot_name });
        try out.writer().print("  br {s} -> L_{s}_{d}_OBJ_TERNARY_TRUE, L_{s}_{d}_OBJ_TERNARY_FALSE\n", .{ cond_name, label_prefix, idx, label_prefix, idx });
        try out.writer().print("L_{s}_{d}_OBJ_TERNARY_TRUE:\n", .{ label_prefix, idx });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
        try out.writer().print("  {s} = add {s}, 1\n", .{ true_cap_name, true_slice.len_name });
        try out.writer().print("  {s} = call @sax_json_write_object_members(*{s}, {s}, *{s}, {s}, {})\n", .{ true_written_name, true_slice.ptr_name, true_slice.len_name, dst_name, true_cap_name, prefix_comma });
        try out.writer().print("  {s} = {s}\n", .{ written_name, true_written_name });
        try out.writer().print("  jmp L_{s}_{d}_OBJ_TERNARY_DONE\n", .{ label_prefix, idx });
        try out.writer().print("L_{s}_{d}_OBJ_TERNARY_FALSE:\n", .{ label_prefix, idx });
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
        try out.writer().print("  {s} = add {s}, 1\n", .{ false_cap_name, false_slice.len_name });
        try out.writer().print("  {s} = call @sax_json_write_object_members(*{s}, {s}, *{s}, {s}, {})\n", .{ false_written_name, false_slice.ptr_name, false_slice.len_name, dst_name, false_cap_name, prefix_comma });
        try out.writer().print("  {s} = {s}\n", .{ written_name, false_written_name });
        try out.writer().print("L_{s}_{d}_OBJ_TERNARY_DONE:\n", .{ label_prefix, idx });
        try out.writer().print("  {s} = add {s}, {s}\n", .{ len_name, len_name, written_name });
        return written_name;
    }

    fn emitJsonTextCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        txt: []const u8,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
        previous_leading_spread_written: ?[]const u8,
    ) !void {
        if (txt.len == 0) return;
        const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(dst_name);

        if (previous_leading_spread_written) |written_name| {
            if (txt[0] == ',') {
                const comma_idx = try self.string_pool.add(",");
                const comma_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, comma_idx });
                defer self.allocator.free(comma_const);
                const tail_idx = if (txt.len > 1) try self.string_pool.add(txt[1..]) else 0;
                const tail_const = if (txt.len > 1) try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, tail_idx }) else try self.allocator.dupe(u8, "");
                defer self.allocator.free(tail_const);
                const label_prefix = try self.allocLabelPrefix(prefix);
                defer self.allocator.free(label_prefix);
                const has_members_name = try std.fmt.allocPrint(self.allocator, "{s}_json_obj_has_members_{d}", .{ prefix, idx });
                defer self.allocator.free(has_members_name);
                const comma_dst_name = try std.fmt.allocPrint(self.allocator, "{s}_comma_dst_{d}", .{ prefix, idx });
                defer self.allocator.free(comma_dst_name);
                try out.writer().print("  {s} = ne {s}, 0\n", .{ has_members_name, written_name });
                try out.writer().print("  br {s} -> L_{s}_{d}_JSON_COMMA, L_{s}_{d}_JSON_COMMA_DONE\n", .{ has_members_name, label_prefix, idx, label_prefix, idx });
                try out.writer().print("L_{s}_{d}_JSON_COMMA:\n", .{ label_prefix, idx });
                try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ comma_dst_name, buf_name, len_name });
                try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, 1)\n", .{ comma_dst_name, comma_const });
                try out.writer().print("  {s} = add {s}, 1\n", .{ len_name, len_name });
                try out.writer().print("L_{s}_{d}_JSON_COMMA_DONE:\n", .{ label_prefix, idx });
                if (txt.len == 1) return;
                try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
                try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, {})\n", .{ dst_name, tail_const, txt.len - 1 });
                try out.writer().print("  {s} = add {s}, {}\n", .{ len_name, len_name, txt.len - 1 });
                return;
            }
        }

        const text_idx = try self.string_pool.add(txt);
        const text_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, text_idx });
        defer self.allocator.free(text_const);
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, {})\n", .{ dst_name, text_const, txt.len });
        try out.writer().print("  {s} = add {s}, {}\n", .{ len_name, len_name, txt.len });
    }

    fn emitStoreState(self: *const SaxLowerer, out: *std.ArrayList(u8), name: []const u8, value: []const u8, ty: parser.StateType) !void {
        if (self.stateVarIndex(name) == null) return LowerError.UnknownStateVar;
        const slot_name = try self.stateSlotConstName(name);
        defer self.allocator.free(slot_name);
        try out.writer().print("  store state+{s}, {s} as {s}\n", .{ slot_name, value, stateTypeName(ty) });
    }

    fn emitStringSliceCopy(self: *const SaxLowerer, out: *std.ArrayList(u8), dst_ptr: []const u8, src_const_idx: usize) !void {
        const const_name = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, src_const_idx });
        defer self.allocator.free(const_name);
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, {})\n", .{ dst_ptr, const_name, self.string_pool.items.items[src_const_idx].len });
    }

    fn emitLoadStateStringSlice(
        self: *const SaxLowerer,
        out: *std.ArrayList(u8),
        state_name: []const u8,
        prefix: []const u8,
    ) !StateStringSlice {
        const sv = self.stateVar(state_name) orelse return LowerError.UnknownStateVar;
        if (sv.ty != .ptr) return LowerError.InvalidTextExpression;

        const ptr_name = try std.fmt.allocPrint(self.allocator, "{s}_ptr", .{prefix});
        errdefer self.allocator.free(ptr_name);
        const len_name = try std.fmt.allocPrint(self.allocator, "{s}_len", .{prefix});
        errdefer self.allocator.free(len_name);

        const slot_name = try self.stateSlotConstName(state_name);
        defer self.allocator.free(slot_name);
        try out.writer().print("  {s} = load state+{s} as ptr\n", .{ ptr_name, slot_name });

        const state_len_name = try self.stateLenVarName(state_name);
        defer self.allocator.free(state_len_name);
        if (self.stateVar(state_len_name)) |_| {
            const len_slot = try self.stateSlotConstName(state_len_name);
            defer self.allocator.free(len_slot);
            try out.writer().print("  {s} = load state+{s} as i64\n", .{ len_name, len_slot });
        } else {
            try out.writer().print("  {s} = {}\n", .{ len_name, sv.alloc_size orelse 0 });
        }

        return .{ .ptr_name = ptr_name, .len_name = len_name };
    }

    fn emitTemplateBuffer(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        pieces: []const parser.TextPiece,
        prefix: []const u8,
    ) !StateStringSlice {
        const buf_name = try std.fmt.allocPrint(self.allocator, "{s}_buf", .{prefix});
        errdefer self.allocator.free(buf_name);
        const len_name = try std.fmt.allocPrint(self.allocator, "{s}_len", .{prefix});
        errdefer self.allocator.free(len_name);

        try out.writer().print("  {s} = stack_alloc {}\n", .{ buf_name, self.templateBufferSize(pieces) });
        try out.writer().print("  {s} = 0\n", .{len_name});

        for (pieces, 0..) |piece, idx| {
            switch (piece) {
                .text => |txt| {
                    const text_idx = try self.string_pool.add(txt);
                    const text_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, text_idx });
                    defer self.allocator.free(text_const);
                    const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_dst_{d}", .{ prefix, idx });
                    defer self.allocator.free(dst_name);
                    try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
                    try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, {})\n", .{ dst_name, text_const, txt.len });
                    try out.writer().print("  {s} = add {s}, {}\n", .{ len_name, len_name, txt.len });
                },
                .json_string_interpolation => return LowerError.InvalidTextExpression,
                .json_object_spread => return LowerError.InvalidTextExpression,
                .interpolation => |expr| {
                    if (self.parseStaticStringTernary(expr)) |ternary| {
                        try self.emitStaticStringTernaryCopy(out, ternary, buf_name, len_name, prefix, idx);
                        continue;
                    }
                    if (simpleStateExprName(expr)) |name| {
                        if (self.stateVar(name)) |sv| {
                            if (sv.ty == .ptr) {
                                const slice_prefix = try std.fmt.allocPrint(self.allocator, "{s}_str_{d}", .{ prefix, idx });
                                defer self.allocator.free(slice_prefix);
                                const slice = try self.emitLoadStateStringSlice(out, name, slice_prefix);
                                defer self.allocator.free(slice.ptr_name);
                                defer self.allocator.free(slice.len_name);
                                const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_dst_{d}", .{ prefix, idx });
                                defer self.allocator.free(dst_name);
                                try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
                                try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, {s})\n", .{ dst_name, slice.ptr_name, slice.len_name });
                                try out.writer().print("  {s} = add {s}, {s}\n", .{ len_name, len_name, slice.len_name });
                                continue;
                            }
                            if (sv.ty == .i1) {
                                const slot_name = try self.stateSlotConstName(name);
                                defer self.allocator.free(slot_name);
                                const bool_name = try std.fmt.allocPrint(self.allocator, "{s}_bool_{d}", .{ prefix, idx });
                                defer self.allocator.free(bool_name);
                                try out.writer().print("  {s} = load state+{s} as i1\n", .{ bool_name, slot_name });
                                try self.emitJsonBoolLiteralCopy(out, bool_name, buf_name, len_name, prefix, idx);
                                continue;
                            }
                        }
                    }

                    var expr_arena = std.heap.ArenaAllocator.init(self.allocator);
                    defer expr_arena.deinit();
                    const expr_prefix = try std.fmt.allocPrint(self.allocator, "{s}_expr_{d}", .{ prefix, idx });
                    defer self.allocator.free(expr_prefix);
                    const value = try self.emitInterpolationExpr(out, expr, expr_prefix, expr_arena.allocator());
                    const tmp_buf_name = try std.fmt.allocPrint(self.allocator, "{s}_tmp_{d}", .{ prefix, idx });
                    defer self.allocator.free(tmp_buf_name);
                    const tmp_len_name = try std.fmt.allocPrint(self.allocator, "{s}_tmp_len_{d}", .{ prefix, idx });
                    defer self.allocator.free(tmp_len_name);
                    const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_dst_{d}", .{ prefix, idx });
                    defer self.allocator.free(dst_name);
                    try out.writer().print("  {s} = stack_alloc 64\n", .{tmp_buf_name});
                    try self.emitFormatInterpolationValue(out, value, tmp_buf_name, tmp_len_name);
                    try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
                    try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, {s})\n", .{ dst_name, tmp_buf_name, tmp_len_name });
                    try out.writer().print("  {s} = add {s}, {s}\n", .{ len_name, len_name, tmp_len_name });
                },
            }
        }

        return .{ .ptr_name = buf_name, .len_name = len_name };
    }

    fn parseStaticStringCondition(self: *const SaxLowerer, text: []const u8) ?StaticStringCondition {
        const trimmed = trimEnclosingParens(std.mem.trim(u8, text, " \t\r\n"));
        if (findTopLevelAnd(trimmed)) |and_idx| {
            const left_text = std.mem.trim(u8, trimmed[0..and_idx], " \t\r\n");
            const right_text = std.mem.trim(u8, trimmed[and_idx + 2 ..], " \t\r\n");

            if (self.parseStaticStringCondition(left_text)) |left_cond| {
                if (self.parseStaticStringCondition(right_text)) |right_cond| {
                    if (self.tryBuildStaticEqChain(left_cond, right_cond)) |chain| {
                        return .{ .static_eq_chain = chain };
                    }
                    switch (left_cond) {
                        .and_truthy => return null,
                        .state_truthy => |left_name| switch (right_cond) {
                            .state_truthy => |right_name| {
                                const left_sv = self.stateVar(left_name) orelse return null;
                                const right_sv = self.stateVar(right_name) orelse return null;
                                if (!isTruthyConditionState(left_sv.ty) or !isTruthyConditionState(right_sv.ty)) return null;
                                return .{ .and_truthy = .{ .left_name = left_name, .right_name = right_name } };
                            },
                            else => return null,
                        },
                        .ptr_eq_literal => |left_eq| switch (right_cond) {
                            .ptr_eq_literal => |right_eq| {
                                var items: [8]PtrEqLiteralConditionItem = undefined;
                                items[0] = .{ .state_name = left_eq.state_name, .literal = left_eq.literal };
                                items[1] = .{ .state_name = right_eq.state_name, .literal = right_eq.literal };
                                return .{ .ptr_eq_literal_chain = .{ .count = 2, .items = items } };
                            },
                            .ptr_eq_literal_chain => |right_chain| {
                                if (right_chain.count + 1 > 8) return null;
                                var items: [8]PtrEqLiteralConditionItem = undefined;
                                items[0] = .{ .state_name = left_eq.state_name, .literal = left_eq.literal };
                                @memcpy(items[1 .. 1 + right_chain.count], right_chain.items[0..right_chain.count]);
                                return .{ .ptr_eq_literal_chain = .{ .count = right_chain.count + 1, .items = items } };
                            },
                            else => return null,
                        },
                        .ptr_eq_literal_chain => |left_chain| switch (right_cond) {
                            .ptr_eq_literal => |right_eq| {
                                if (left_chain.count + 1 > 8) return null;
                                var items: [8]PtrEqLiteralConditionItem = undefined;
                                @memcpy(items[0..left_chain.count], left_chain.items[0..left_chain.count]);
                                items[left_chain.count] = .{ .state_name = right_eq.state_name, .literal = right_eq.literal };
                                return .{ .ptr_eq_literal_chain = .{ .count = left_chain.count + 1, .items = items } };
                            },
                            .ptr_eq_literal_chain => |right_chain| {
                                if (left_chain.count + right_chain.count > 8) return null;
                                var items: [8]PtrEqLiteralConditionItem = undefined;
                                @memcpy(items[0..left_chain.count], left_chain.items[0..left_chain.count]);
                                @memcpy(items[left_chain.count .. left_chain.count + right_chain.count], right_chain.items[0..right_chain.count]);
                                return .{ .ptr_eq_literal_chain = .{ .count = left_chain.count + right_chain.count, .items = items } };
                            },
                            else => return null,
                        },
                        .static_eq_chain => return null,
                    }
                }
            }
            return null;
        }

        if (findTopLevelEq(trimmed)) |eq_idx| {
            const left_text = std.mem.trim(u8, trimmed[0..eq_idx], " \t\r\n");
            const right_text = std.mem.trim(u8, trimmed[eq_idx + 2 ..], " \t\r\n");
            const state_name = simpleStateNameText(trimEnclosingParens(left_text)) orelse return null;
            const sv = self.stateVar(state_name) orelse return null;
            switch (sv.ty) {
                .ptr => {
                    const literal = parseStaticStringLiteral(right_text) orelse return null;
                    return .{ .ptr_eq_literal = .{ .state_name = state_name, .literal = literal } };
                },
                .i1, .i32, .i64 => {
                    const literal = parseStaticIntLiteral(right_text) orelse return null;
                    var items: [8]StaticEqConditionItem = undefined;
                    items[0] = .{ .i64_eq_literal = .{ .state_name = state_name, .literal = literal } };
                    return .{ .static_eq_chain = .{ .count = 1, .items = items } };
                },
                .f64 => return null,
            }
        }

        const condition_name = simpleStateNameText(trimmed) orelse return null;
        const sv = self.stateVar(condition_name) orelse return null;
        if (!isTruthyConditionState(sv.ty)) return null;
        return .{ .state_truthy = condition_name };
    }

    fn tryBuildStaticEqChain(
        self: *const SaxLowerer,
        left_cond: StaticStringCondition,
        right_cond: StaticStringCondition,
    ) ?StaticEqConditionChain {
        _ = self;

        var items: [8]StaticEqConditionItem = undefined;
        var count: usize = 0;

        switch (left_cond) {
            .state_truthy => |state_name| {
                items[count] = .{ .truthy_state = state_name };
                count += 1;
            },
            .ptr_eq_literal => |left_eq| {
                items[count] = .{ .ptr_eq_literal = .{ .state_name = left_eq.state_name, .literal = left_eq.literal } };
                count += 1;
            },
            .static_eq_chain => |left_chain| {
                if (left_chain.count > 8) return null;
                @memcpy(items[0..left_chain.count], left_chain.items[0..left_chain.count]);
                count = left_chain.count;
            },
            else => return null,
        }

        switch (right_cond) {
            .state_truthy => |state_name| {
                if (count + 1 > 8) return null;
                items[count] = .{ .truthy_state = state_name };
                count += 1;
            },
            .ptr_eq_literal => |right_eq| {
                if (count + 1 > 8) return null;
                items[count] = .{ .ptr_eq_literal = .{ .state_name = right_eq.state_name, .literal = right_eq.literal } };
                count += 1;
            },
            .static_eq_chain => |right_chain| {
                if (count + right_chain.count > 8) return null;
                @memcpy(items[count .. count + right_chain.count], right_chain.items[0..right_chain.count]);
                count += right_chain.count;
            },
            else => return null,
        }

        if (count < 2) return null;
        return .{ .count = count, .items = items };
    }

    fn parseStaticStringTernary(self: *const SaxLowerer, expr: parser.Expr) ?StaticStringTernary {
        const text = trimEnclosingParens(std.mem.trim(u8, expr.expr, " \t\r\n"));
        const question_idx = findTopLevelByte(text, '?') orelse return null;
        const condition_text = std.mem.trim(u8, text[0..question_idx], " \t\r\n");
        const condition = self.parseStaticStringCondition(condition_text) orelse return null;

        const rest = text[question_idx + 1 ..];
        const colon_idx = findTopLevelByte(rest, ':') orelse return null;
        const true_text = parseStaticStringLiteral(rest[0..colon_idx]) orelse return null;
        const false_text = parseStaticStringLiteral(rest[colon_idx + 1 ..]) orelse return null;
        return .{ .condition = condition, .true_text = true_text, .false_text = false_text };
    }

    fn isTruthyConditionState(ty: parser.StateType) bool {
        return switch (ty) {
            .i1, .i32, .i64 => true,
            .f64, .ptr => false,
        };
    }

    fn findTopLevelAnd(text: []const u8) ?usize {
        var depth: usize = 0;
        var idx: usize = 0;
        while (idx + 1 < text.len) : (idx += 1) {
            const c = text[idx];
            switch (c) {
                '(', '[', '{' => depth += 1,
                ')', ']', '}' => {
                    if (depth > 0) depth -= 1;
                },
                '&' => {
                    if (depth == 0 and text[idx + 1] == '&') return idx;
                },
                else => {},
            }
        }
        return null;
    }

    fn findTopLevelEq(text: []const u8) ?usize {
        var depth: usize = 0;
        var idx: usize = 0;
        while (idx + 1 < text.len) : (idx += 1) {
            const c = text[idx];
            switch (c) {
                '(', '[', '{' => depth += 1,
                ')', ']', '}' => {
                    if (depth > 0) depth -= 1;
                },
                '=' => {
                    if (depth == 0 and text[idx + 1] == '=') return idx;
                },
                else => {},
            }
        }
        return null;
    }

    fn parseStaticStringLiteral(text: []const u8) ?[]const u8 {
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        if (trimmed.len < 2) return null;
        const quote = trimmed[0];
        if ((quote != '"' and quote != '\'') or trimmed[trimmed.len - 1] != quote) return null;
        const body = trimmed[1 .. trimmed.len - 1];
        for (body) |c| {
            if (c == quote or c == '\\' or c < 0x20) return null;
        }
        return body;
    }

    fn parseStaticIntLiteral(text: []const u8) ?i64 {
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        return std.fmt.parseInt(i64, trimmed, 10) catch null;
    }

    fn emitStaticStringTernaryCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        ternary: StaticStringTernary,
        buf_name: []const u8,
        len_name: []const u8,
        prefix: []const u8,
        idx: usize,
    ) !void {
        const bool_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_bool_{d}", .{ prefix, idx });
        defer self.allocator.free(bool_name);
        const label_prefix = try self.allocLabelPrefix(prefix);
        defer self.allocator.free(label_prefix);
        const true_label = try std.fmt.allocPrint(self.allocator, "L_{s}_TERNARY_TRUE_{d}", .{ label_prefix, idx });
        defer self.allocator.free(true_label);
        const false_label = try std.fmt.allocPrint(self.allocator, "L_{s}_TERNARY_FALSE_{d}", .{ label_prefix, idx });
        defer self.allocator.free(false_label);
        const done_label = try std.fmt.allocPrint(self.allocator, "L_{s}_TERNARY_DONE_{d}", .{ label_prefix, idx });
        defer self.allocator.free(done_label);
        const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_dst_{d}", .{ prefix, idx });
        defer self.allocator.free(dst_name);
        const written_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_written_{d}", .{ prefix, idx });
        defer self.allocator.free(written_name);

        try out.writer().print("  {s} = 0\n", .{written_name});
        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
        switch (ternary.condition) {
            .state_truthy => |state_name| {
                const slot_name = try self.stateSlotConstName(state_name);
                defer self.allocator.free(slot_name);
                const sv = self.stateVar(state_name).?;
                switch (sv.ty) {
                    .i1 => try out.writer().print("  {s} = load state+{s} as i1\n", .{ bool_name, slot_name }),
                    .i32 => {
                        const raw_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_raw_{d}", .{ prefix, idx });
                        defer self.allocator.free(raw_name);
                        try out.writer().print("  {s} = load state+{s} as i32\n", .{ raw_name, slot_name });
                        try out.writer().print("  {s} = ne {s}, 0\n", .{ bool_name, raw_name });
                    },
                    .i64 => {
                        const raw_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_raw_{d}", .{ prefix, idx });
                        defer self.allocator.free(raw_name);
                        try out.writer().print("  {s} = load state+{s} as i64\n", .{ raw_name, slot_name });
                        try out.writer().print("  {s} = ne {s}, 0\n", .{ bool_name, raw_name });
                    },
                    .f64, .ptr => return LowerError.InvalidTextExpression,
                }
            },
            .and_truthy => |and_cond| {
                const left_bool = try std.fmt.allocPrint(self.allocator, "{s}_ternary_left_bool_{d}", .{ prefix, idx });
                defer self.allocator.free(left_bool);
                const right_bool = try std.fmt.allocPrint(self.allocator, "{s}_ternary_right_bool_{d}", .{ prefix, idx });
                defer self.allocator.free(right_bool);
                try self.emitTruthyStateLoad(out, and_cond.left_name, left_bool, prefix, idx, "left");
                try self.emitTruthyStateLoad(out, and_cond.right_name, right_bool, prefix, idx, "right");
                try out.writer().print("  {s} = and {s}, {s}\n", .{ bool_name, left_bool, right_bool });
            },
            .ptr_eq_literal => |eq_cond| {
                const slice_prefix = try std.fmt.allocPrint(self.allocator, "{s}_ternary_eq_{d}", .{ prefix, idx });
                defer self.allocator.free(slice_prefix);
                const slice = try self.emitLoadStateStringSlice(out, eq_cond.state_name, slice_prefix);
                defer self.allocator.free(slice.ptr_name);
                defer self.allocator.free(slice.len_name);
                const literal_idx = try self.string_pool.add(eq_cond.literal);
                const literal_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, literal_idx });
                defer self.allocator.free(literal_const);
                const cmp_len_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_eq_len_{d}", .{ prefix, idx });
                defer self.allocator.free(cmp_len_name);
                const cmp_mem_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_eq_mem_{d}", .{ prefix, idx });
                defer self.allocator.free(cmp_mem_name);
                try out.writer().print("  {s} = eq {s}, {}\n", .{ cmp_len_name, slice.len_name, eq_cond.literal.len });
                try out.writer().print("  {s} = call @sax_mem_eq(*{s}, *{s}, {})\n", .{ cmp_mem_name, slice.ptr_name, literal_const, eq_cond.literal.len });
                try out.writer().print("  {s} = and {s}, {s}\n", .{ bool_name, cmp_len_name, cmp_mem_name });
            },
            .ptr_eq_literal_chain => |chain_cond| {
                var previous_bool_name: ?[]const u8 = null;
                var temp_bool_names = std.ArrayList([]const u8).init(self.allocator);
                defer {
                    for (temp_bool_names.items) |name| self.allocator.free(name);
                    temp_bool_names.deinit();
                }
                for (chain_cond.items[0..chain_cond.count], 0..) |item, chain_idx| {
                    const slice_prefix = try std.fmt.allocPrint(self.allocator, "{s}_ternary_eq_{d}_{d}", .{ prefix, idx, chain_idx });
                    defer self.allocator.free(slice_prefix);
                    const slice = try self.emitLoadStateStringSlice(out, item.state_name, slice_prefix);
                    defer self.allocator.free(slice.ptr_name);
                    defer self.allocator.free(slice.len_name);

                    const literal_idx = try self.string_pool.add(item.literal);
                    const literal_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, literal_idx });
                    defer self.allocator.free(literal_const);
                    const cmp_len_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_eq_len_{d}_{d}", .{ prefix, idx, chain_idx });
                    defer self.allocator.free(cmp_len_name);
                    const cmp_mem_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_eq_mem_{d}_{d}", .{ prefix, idx, chain_idx });
                    defer self.allocator.free(cmp_mem_name);
                    const item_bool_name = if (chain_idx + 1 == chain_cond.count)
                        bool_name
                    else
                        try std.fmt.allocPrint(self.allocator, "{s}_ternary_eq_bool_{d}_{d}", .{ prefix, idx, chain_idx });
                    if (chain_idx + 1 != chain_cond.count) try temp_bool_names.append(item_bool_name);

                    try out.writer().print("  {s} = eq {s}, {}\n", .{ cmp_len_name, slice.len_name, item.literal.len });
                    try out.writer().print("  {s} = call @sax_mem_eq(*{s}, *{s}, {})\n", .{ cmp_mem_name, slice.ptr_name, literal_const, item.literal.len });

                    if (previous_bool_name) |prev| {
                        const combined_name = if (chain_idx + 1 == chain_cond.count)
                            bool_name
                        else
                            item_bool_name;
                        const current_bool_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_eq_current_bool_{d}_{d}", .{ prefix, idx, chain_idx });
                        defer self.allocator.free(current_bool_name);
                        try out.writer().print("  {s} = and {s}, {s}\n", .{ current_bool_name, cmp_len_name, cmp_mem_name });
                        try out.writer().print("  {s} = and {s}, {s}\n", .{ combined_name, prev, current_bool_name });
                        previous_bool_name = combined_name;
                    } else {
                        try out.writer().print("  {s} = and {s}, {s}\n", .{ item_bool_name, cmp_len_name, cmp_mem_name });
                        previous_bool_name = item_bool_name;
                    }
                }
            },
            .static_eq_chain => |chain_cond| {
                var previous_bool_name: ?[]const u8 = null;
                var temp_bool_names = std.ArrayList([]const u8).init(self.allocator);
                defer {
                    for (temp_bool_names.items) |name| self.allocator.free(name);
                    temp_bool_names.deinit();
                }

                for (chain_cond.items[0..chain_cond.count], 0..) |item, chain_idx| {
                    const item_bool_name = if (chain_idx + 1 == chain_cond.count)
                        bool_name
                    else
                        try std.fmt.allocPrint(self.allocator, "{s}_ternary_static_eq_bool_{d}_{d}", .{ prefix, idx, chain_idx });
                    if (chain_idx + 1 != chain_cond.count) try temp_bool_names.append(item_bool_name);

                    const current_bool_name = switch (item) {
                        .truthy_state => |state_name| blk: {
                            const truthy_bool_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_static_eq_truthy_bool_{d}_{d}", .{ prefix, idx, chain_idx });
                            try temp_bool_names.append(truthy_bool_name);
                            const side_name = try std.fmt.allocPrint(self.allocator, "static_eq_truthy_{d}", .{chain_idx});
                            defer self.allocator.free(side_name);
                            try self.emitTruthyStateLoad(out, state_name, truthy_bool_name, prefix, idx, side_name);
                            break :blk truthy_bool_name;
                        },
                        .ptr_eq_literal => |eq_item| blk: {
                            const slice_prefix = try std.fmt.allocPrint(self.allocator, "{s}_ternary_static_eq_ptr_{d}_{d}", .{ prefix, idx, chain_idx });
                            defer self.allocator.free(slice_prefix);
                            const slice = try self.emitLoadStateStringSlice(out, eq_item.state_name, slice_prefix);
                            defer self.allocator.free(slice.ptr_name);
                            defer self.allocator.free(slice.len_name);

                            const literal_idx = try self.string_pool.add(eq_item.literal);
                            const literal_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, literal_idx });
                            defer self.allocator.free(literal_const);
                            const cmp_len_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_static_eq_ptr_len_{d}_{d}", .{ prefix, idx, chain_idx });
                            defer self.allocator.free(cmp_len_name);
                            const cmp_mem_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_static_eq_ptr_mem_{d}_{d}", .{ prefix, idx, chain_idx });
                            defer self.allocator.free(cmp_mem_name);
                            const ptr_bool_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_static_eq_ptr_bool_{d}_{d}", .{ prefix, idx, chain_idx });
                            try temp_bool_names.append(ptr_bool_name);

                            try out.writer().print("  {s} = eq {s}, {}\n", .{ cmp_len_name, slice.len_name, eq_item.literal.len });
                            try out.writer().print("  {s} = call @sax_mem_eq(*{s}, *{s}, {})\n", .{ cmp_mem_name, slice.ptr_name, literal_const, eq_item.literal.len });
                            try out.writer().print("  {s} = and {s}, {s}\n", .{ ptr_bool_name, cmp_len_name, cmp_mem_name });
                            break :blk ptr_bool_name;
                        },
                        .i64_eq_literal => |eq_item| blk: {
                            const slot_name = try self.stateSlotConstName(eq_item.state_name);
                            defer self.allocator.free(slot_name);
                            const sv = self.stateVar(eq_item.state_name) orelse return LowerError.UnknownStateVar;
                            const load_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_static_eq_i64_load_{d}_{d}", .{ prefix, idx, chain_idx });
                            defer self.allocator.free(load_name);
                            switch (sv.ty) {
                                .i1 => {
                                    const raw_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_static_eq_i1_raw_{d}_{d}", .{ prefix, idx, chain_idx });
                                    defer self.allocator.free(raw_name);
                                    try out.writer().print("  {s} = load state+{s} as i1\n", .{ raw_name, slot_name });
                                    try out.writer().print("  {s} = zext {s} as i64\n", .{ load_name, raw_name });
                                },
                                .i32 => {
                                    const raw_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_static_eq_i32_raw_{d}_{d}", .{ prefix, idx, chain_idx });
                                    defer self.allocator.free(raw_name);
                                    try out.writer().print("  {s} = load state+{s} as i32\n", .{ raw_name, slot_name });
                                    try out.writer().print("  {s} = sext {s} as i64\n", .{ load_name, raw_name });
                                },
                                .i64 => try out.writer().print("  {s} = load state+{s} as i64\n", .{ load_name, slot_name }),
                                .f64, .ptr => return LowerError.InvalidTextExpression,
                            }
                            const int_bool_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_static_eq_i64_bool_{d}_{d}", .{ prefix, idx, chain_idx });
                            try temp_bool_names.append(int_bool_name);
                            try out.writer().print("  {s} = eq {s}, {}\n", .{ int_bool_name, load_name, eq_item.literal });
                            break :blk int_bool_name;
                        },
                    };

                    if (previous_bool_name) |prev| {
                        try out.writer().print("  {s} = and {s}, {s}\n", .{ item_bool_name, prev, current_bool_name });
                        previous_bool_name = item_bool_name;
                    } else {
                        if (chain_idx + 1 == chain_cond.count) {
                            try out.writer().print("  {s} = and {s}, {s}\n", .{ bool_name, current_bool_name, current_bool_name });
                            previous_bool_name = bool_name;
                        } else {
                            previous_bool_name = current_bool_name;
                        }
                    }
                }
            },
        }
        try out.writer().print("  br {s} -> {s}, {s}\n", .{ bool_name, true_label, false_label });
        try out.writer().print("{s}:\n", .{true_label});
        try self.emitStaticTemplateTextBranchCopy(out, ternary.true_text, dst_name, written_name);
        try out.writer().print("  jmp {s}\n", .{done_label});
        try out.writer().print("{s}:\n", .{false_label});
        try self.emitStaticTemplateTextBranchCopy(out, ternary.false_text, dst_name, written_name);
        try out.writer().print("  jmp {s}\n", .{done_label});
        try out.writer().print("{s}:\n", .{done_label});
        try out.writer().print("  {s} = add {s}, {s}\n", .{ len_name, len_name, written_name });
    }

    fn emitTruthyStateLoad(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        state_name: []const u8,
        bool_name: []const u8,
        prefix: []const u8,
        idx: usize,
        side: []const u8,
    ) !void {
        const slot_name = try self.stateSlotConstName(state_name);
        defer self.allocator.free(slot_name);
        const sv = self.stateVar(state_name) orelse return LowerError.UnknownStateVar;
        switch (sv.ty) {
            .i1 => try out.writer().print("  {s} = load state+{s} as i1\n", .{ bool_name, slot_name }),
            .i32 => {
                const raw_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_{s}_raw_{d}", .{ prefix, side, idx });
                defer self.allocator.free(raw_name);
                try out.writer().print("  {s} = load state+{s} as i32\n", .{ raw_name, slot_name });
                try out.writer().print("  {s} = ne {s}, 0\n", .{ bool_name, raw_name });
            },
            .i64 => {
                const raw_name = try std.fmt.allocPrint(self.allocator, "{s}_ternary_{s}_raw_{d}", .{ prefix, side, idx });
                defer self.allocator.free(raw_name);
                try out.writer().print("  {s} = load state+{s} as i64\n", .{ raw_name, slot_name });
                try out.writer().print("  {s} = ne {s}, 0\n", .{ bool_name, raw_name });
            },
            .f64, .ptr => return LowerError.InvalidTextExpression,
        }
    }

    fn emitStaticTemplateTextBranchCopy(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        text: []const u8,
        dst_name: []const u8,
        written_name: []const u8,
    ) !void {
        if (text.len == 0) {
            try out.writer().print("  {s} = 0\n", .{written_name});
            return;
        }
        const text_idx = try self.string_pool.add(text);
        const text_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, text_idx });
        defer self.allocator.free(text_const);
        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, {})\n", .{ dst_name, text_const, text.len });
        try out.writer().print("  {s} = {}\n", .{ written_name, text.len });
    }

    fn emitJsonTemplateBuffer(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        pieces: []const parser.TextPiece,
        prefix: []const u8,
    ) !StateStringSlice {
        const buf_name = try std.fmt.allocPrint(self.allocator, "{s}_buf", .{prefix});
        errdefer self.allocator.free(buf_name);
        const len_name = try std.fmt.allocPrint(self.allocator, "{s}_len", .{prefix});
        errdefer self.allocator.free(len_name);

        try out.writer().print("  {s} = stack_alloc {}\n", .{ buf_name, self.jsonTemplateBufferSize(pieces) });
        try out.writer().print("  {s} = 0\n", .{len_name});

        var previous_leading_spread_written: ?[]const u8 = null;
        defer {
            if (previous_leading_spread_written) |name| self.allocator.free(name);
        }

        for (pieces, 0..) |piece, idx| {
            switch (piece) {
                .text => |txt| {
                    try self.emitJsonTextCopy(out, txt, buf_name, len_name, prefix, idx, previous_leading_spread_written);
                    if (previous_leading_spread_written) |name| {
                        self.allocator.free(name);
                        previous_leading_spread_written = null;
                    }
                },
                .json_string_interpolation => |expr| {
                    if (previous_leading_spread_written) |name| {
                        self.allocator.free(name);
                        previous_leading_spread_written = null;
                    }
                    try self.emitJsonStringInterpolationCopy(out, expr, buf_name, len_name, prefix, idx);
                },
                .json_object_spread => |spread| {
                    if (previous_leading_spread_written) |name| {
                        self.allocator.free(name);
                        previous_leading_spread_written = null;
                    }
                    const written_name = try self.emitJsonObjectSpreadCopy(out, spread, buf_name, len_name, prefix, idx);
                    if (!spread.prefix_comma) previous_leading_spread_written = written_name else self.allocator.free(written_name);
                },
                .interpolation => |expr| {
                    if (previous_leading_spread_written) |name| {
                        self.allocator.free(name);
                        previous_leading_spread_written = null;
                    }
                    if (try self.parseJsonI1ValueTernary(expr)) |ternary| {
                        try self.emitJsonI1ValueTernaryCopy(out, ternary, buf_name, len_name, prefix, idx);
                        continue;
                    }
                    if (try self.parseJsonI64ValueTernary(expr)) |ternary| {
                        try self.emitJsonI64ValueTernaryCopy(out, ternary, buf_name, len_name, prefix, idx);
                        continue;
                    }
                    if (try self.parseJsonI32ValueTernary(expr)) |ternary| {
                        try self.emitJsonI32ValueTernaryCopy(out, ternary, buf_name, len_name, prefix, idx);
                        continue;
                    }
                    if (try self.parseJsonF64ValueTernary(expr)) |ternary| {
                        try self.emitJsonF64ValueTernaryCopy(out, ternary, buf_name, len_name, prefix, idx);
                        continue;
                    }
                    if (try self.parseJsonStringValueTernary(expr)) |ternary| {
                        defer self.freeJsonStringValueTernary(ternary);
                        try self.emitJsonStringValueTernaryCopy(out, ternary, buf_name, len_name, prefix, idx);
                        continue;
                    }
                    if (simpleStateExprName(expr)) |name| {
                        if (self.stateVar(name)) |sv| {
                            if (sv.ty == .ptr) {
                                try self.emitJsonEscapedStringCopy(out, name, buf_name, len_name, prefix, idx);
                                continue;
                            }
                            if (sv.ty == .i1) {
                                const slot_name = try self.stateSlotConstName(name);
                                defer self.allocator.free(slot_name);
                                const bool_name = try std.fmt.allocPrint(self.allocator, "{s}_bool_{d}", .{ prefix, idx });
                                defer self.allocator.free(bool_name);
                                try out.writer().print("  {s} = load state+{s} as i1\n", .{ bool_name, slot_name });
                                try self.emitJsonBoolLiteralCopy(out, bool_name, buf_name, len_name, prefix, idx);
                                continue;
                            }
                        }
                    }

                    var expr_arena = std.heap.ArenaAllocator.init(self.allocator);
                    defer expr_arena.deinit();
                    const expr_prefix = try std.fmt.allocPrint(self.allocator, "{s}_expr_{d}", .{ prefix, idx });
                    defer self.allocator.free(expr_prefix);
                    const value = try self.emitInterpolationExpr(out, expr, expr_prefix, expr_arena.allocator());
                    const tmp_buf_name = try std.fmt.allocPrint(self.allocator, "{s}_tmp_{d}", .{ prefix, idx });
                    defer self.allocator.free(tmp_buf_name);
                    const tmp_len_name = try std.fmt.allocPrint(self.allocator, "{s}_tmp_len_{d}", .{ prefix, idx });
                    defer self.allocator.free(tmp_len_name);
                    const dst_name = try std.fmt.allocPrint(self.allocator, "{s}_dst_{d}", .{ prefix, idx });
                    defer self.allocator.free(dst_name);
                    try out.writer().print("  {s} = stack_alloc 64\n", .{tmp_buf_name});
                    try self.emitFormatInterpolationValue(out, value, tmp_buf_name, tmp_len_name);
                    try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, len_name });
                    try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, {s})\n", .{ dst_name, tmp_buf_name, tmp_len_name });
                    try out.writer().print("  {s} = add {s}, {s}\n", .{ len_name, len_name, tmp_len_name });
                },
            }
        }

        return .{ .ptr_name = buf_name, .len_name = len_name };
    }

    fn emitJsonNormalizeObjectBuffer(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        source: StateStringSlice,
        prefix: []const u8,
        cap_size: usize,
    ) !StateStringSlice {
        const buf_name = try std.fmt.allocPrint(self.allocator, "{s}_normalized_buf", .{prefix});
        errdefer self.allocator.free(buf_name);
        const len_name = try std.fmt.allocPrint(self.allocator, "{s}_normalized_len", .{prefix});
        errdefer self.allocator.free(len_name);
        const normalized_cap = cap_size * 2 + 2;
        try out.writer().print("  {s} = stack_alloc {}\n", .{ buf_name, normalized_cap });
        try out.writer().print("  {s} = call @sax_json_normalize_object(*{s}, {s}, *{s}, {})\n", .{ len_name, source.ptr_name, source.len_name, buf_name, normalized_cap });
        return .{ .ptr_name = buf_name, .len_name = len_name };
    }

    fn simpleStateExprName(expr: parser.Expr) ?[]const u8 {
        return simpleStateNameText(expr.expr);
    }

    fn simpleStateNameText(text: []const u8) ?[]const u8 {
        const name = std.mem.trim(u8, text, " \t\r\n");
        if (name.len == 0 or !std.ascii.isAlphabetic(name[0]) and name[0] != '_') return null;
        for (name[1..]) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '_') return null;
        }
        return name;
    }

    fn simpleI64LiteralText(text: []const u8) ?[]const u8 {
        const literal = std.mem.trim(u8, text, " \t\r\n");
        if (literal.len == 0) return null;
        var start: usize = 0;
        if (literal[0] == '-') {
            if (literal.len == 1) return null;
            start = 1;
        }
        for (literal[start..]) |c| {
            if (!std.ascii.isDigit(c)) return null;
        }
        _ = std.fmt.parseInt(i64, literal, 10) catch return null;
        return literal;
    }

    fn simpleI32LiteralValue(text: []const u8) ?i32 {
        const literal = std.mem.trim(u8, text, " \t\r\n");
        if (literal.len == 0) return null;
        var start: usize = 0;
        if (literal[0] == '-') {
            if (literal.len == 1) return null;
            start = 1;
        }
        for (literal[start..]) |c| {
            if (!std.ascii.isDigit(c)) return null;
        }
        return std.fmt.parseInt(i32, literal, 10) catch null;
    }

    fn simpleI1LiteralValue(text: []const u8) ?bool {
        const literal = std.mem.trim(u8, text, " \t\r\n");
        if (std.mem.eql(u8, literal, "true")) return true;
        if (std.mem.eql(u8, literal, "false")) return false;
        return null;
    }

    fn simpleF64LiteralBits(text: []const u8) ?i64 {
        const literal = std.mem.trim(u8, text, " \t\r\n");
        if (literal.len == 0) return null;
        var has_digit = false;
        var has_float_marker = false;
        for (literal, 0..) |c, idx| {
            if (std.ascii.isDigit(c)) {
                has_digit = true;
                continue;
            }
            if ((c == '+' or c == '-') and (idx == 0 or literal[idx - 1] == 'e' or literal[idx - 1] == 'E')) continue;
            if (c == '.' or c == 'e' or c == 'E') {
                has_float_marker = true;
                continue;
            }
            return null;
        }
        if (!has_digit or !has_float_marker) return null;
        const value = std.fmt.parseFloat(f64, literal) catch return null;
        return @bitCast(value);
    }

    fn parseJsonStringTernaryKey(self: *const SaxLowerer, expr: parser.Expr) !?JsonStringTernaryKey {
        const text = trimEnclosingParens(std.mem.trim(u8, expr.expr, " \t\r\n"));
        const question = findTopLevelByte(text, '?') orelse return null;
        const colon = findTopLevelByte(text[question + 1 ..], ':') orelse return LowerError.InvalidTextExpression;
        const colon_idx = question + 1 + colon;
        const condition_text = std.mem.trim(u8, text[0..question], " \t\r\n");
        const true_text = std.mem.trim(u8, text[question + 1 .. colon_idx], " \t\r\n");
        const false_text = std.mem.trim(u8, text[colon_idx + 1 ..], " \t\r\n");
        const condition_name = simpleStateNameText(condition_text) orelse return LowerError.InvalidTextExpression;
        const sv = self.stateVar(condition_name) orelse return LowerError.UnknownStateVar;
        if (sv.ty != .i1) return LowerError.InvalidTextExpression;
        return .{
            .condition_name = condition_name,
            .true_key_json = try parseSimpleJsonStringKeyLiteral(self.allocator, true_text),
            .false_key_json = try parseSimpleJsonStringKeyLiteral(self.allocator, false_text),
        };
    }

    fn parseJsonStringKeyBranch(self: *const SaxLowerer, text: []const u8) !?JsonStringKeyBranch {
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        if (trimmed.len == 0) return null;
        if (std.mem.eql(u8, trimmed, "null")) {
            return .{ .static_json = try self.allocator.dupe(u8, "\"null\"") };
        }
        if (trimmed[0] == '"' or trimmed[0] == '\'') {
            return .{ .static_json = try parseSimpleJsonStringKeyLiteral(self.allocator, trimmed) };
        }
        const state_name = simpleStateNameText(trimmed) orelse return null;
        const sv = self.stateVar(state_name) orelse return LowerError.UnknownStateVar;
        if (sv.ty != .ptr) return null;
        return .{ .state = state_name };
    }

    fn parseJsonMixedStringTernaryKey(self: *const SaxLowerer, expr: parser.Expr) !?JsonMixedStringTernaryKey {
        const text = trimEnclosingParens(std.mem.trim(u8, expr.expr, " \t\r\n"));
        const question = findTopLevelByte(text, '?') orelse return null;
        const colon = findTopLevelByte(text[question + 1 ..], ':') orelse return LowerError.InvalidTextExpression;
        const colon_idx = question + 1 + colon;
        const condition_text = std.mem.trim(u8, text[0..question], " \t\r\n");
        const true_text = std.mem.trim(u8, text[question + 1 .. colon_idx], " \t\r\n");
        const false_text = std.mem.trim(u8, text[colon_idx + 1 ..], " \t\r\n");
        const condition_name = simpleStateNameText(condition_text) orelse return LowerError.InvalidTextExpression;
        const condition_sv = self.stateVar(condition_name) orelse return LowerError.UnknownStateVar;
        if (condition_sv.ty != .i1) return LowerError.InvalidTextExpression;
        const true_branch = (try self.parseJsonStringKeyBranch(true_text)) orelse return null;
        errdefer switch (true_branch) {
            .state => {},
            .static_json => |json| self.allocator.free(json),
        };
        const false_branch = (try self.parseJsonStringKeyBranch(false_text)) orelse return null;
        return .{
            .condition_name = condition_name,
            .true_branch = true_branch,
            .false_branch = false_branch,
        };
    }

    fn parseJsonPtrStringTernaryKey(self: *const SaxLowerer, expr: parser.Expr) !?JsonPtrStringTernaryKey {
        const text = trimEnclosingParens(std.mem.trim(u8, expr.expr, " \t\r\n"));
        const question = findTopLevelByte(text, '?') orelse return null;
        const colon = findTopLevelByte(text[question + 1 ..], ':') orelse return LowerError.InvalidTextExpression;
        const colon_idx = question + 1 + colon;
        const condition_text = std.mem.trim(u8, text[0..question], " \t\r\n");
        const true_text = std.mem.trim(u8, text[question + 1 .. colon_idx], " \t\r\n");
        const false_text = std.mem.trim(u8, text[colon_idx + 1 ..], " \t\r\n");
        const condition_name = simpleStateNameText(condition_text) orelse return LowerError.InvalidTextExpression;
        const condition_sv = self.stateVar(condition_name) orelse return LowerError.UnknownStateVar;
        if (condition_sv.ty != .i1) return LowerError.InvalidTextExpression;
        const true_state_name = simpleStateNameText(true_text) orelse return null;
        const true_sv = self.stateVar(true_state_name) orelse return LowerError.UnknownStateVar;
        if (true_sv.ty != .ptr) return null;
        const false_state_name = simpleStateNameText(false_text) orelse return null;
        const false_sv = self.stateVar(false_state_name) orelse return LowerError.UnknownStateVar;
        if (false_sv.ty != .ptr) return null;
        return .{
            .condition_name = condition_name,
            .true_state_name = true_state_name,
            .false_state_name = false_state_name,
        };
    }

    fn parseJsonObjectSpreadBranch(self: *const SaxLowerer, text: []const u8) !?JsonObjectSpreadBranch {
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        if (trimmed.len == 0) return null;
        if (std.mem.eql(u8, trimmed, "null")) {
            return .{ .static_json = try self.allocator.dupe(u8, "{}") };
        }
        if (trimmed[0] == '{') {
            const json = parser.parseComponentObjectLiteralJson(self.allocator, trimmed) catch return LowerError.InvalidTextExpression;
            return .{ .static_json = json };
        }
        const state_name = simpleStateNameText(trimmed) orelse return null;
        const sv = self.stateVar(state_name) orelse return LowerError.UnknownStateVar;
        if (sv.ty != .ptr) return null;
        return .{ .state = state_name };
    }

    fn parseJsonObjectSpreadTernary(self: *const SaxLowerer, expr: parser.Expr) !?JsonObjectSpreadTernary {
        const text = trimEnclosingParens(std.mem.trim(u8, expr.expr, " \t\r\n"));
        const question = findTopLevelByte(text, '?') orelse return null;
        const colon = findTopLevelByte(text[question + 1 ..], ':') orelse return LowerError.InvalidTextExpression;
        const colon_idx = question + 1 + colon;
        const condition_text = std.mem.trim(u8, text[0..question], " \t\r\n");
        const true_text = std.mem.trim(u8, text[question + 1 .. colon_idx], " \t\r\n");
        const false_text = std.mem.trim(u8, text[colon_idx + 1 ..], " \t\r\n");
        const condition_name = simpleStateNameText(condition_text) orelse return LowerError.InvalidTextExpression;
        const condition_sv = self.stateVar(condition_name) orelse return LowerError.UnknownStateVar;
        if (condition_sv.ty != .i1) return LowerError.InvalidTextExpression;
        const true_branch = (try self.parseJsonObjectSpreadBranch(true_text)) orelse return LowerError.InvalidTextExpression;
        errdefer switch (true_branch) {
            .state => {},
            .static_json => |json| self.allocator.free(json),
        };
        const false_branch = (try self.parseJsonObjectSpreadBranch(false_text)) orelse return LowerError.InvalidTextExpression;
        return .{
            .condition_name = condition_name,
            .true_branch = true_branch,
            .false_branch = false_branch,
        };
    }

    fn parseJsonObjectSpreadLogicalAnd(self: *const SaxLowerer, expr: parser.Expr) !?JsonObjectSpreadTernary {
        const text = trimEnclosingParens(std.mem.trim(u8, expr.expr, " \t\r\n"));
        const and_idx = findTopLevelToken(text, "&&") orelse return null;
        var condition_text = std.mem.trim(u8, text[0..and_idx], " \t\r\n");
        var negated = false;
        if (condition_text.len > 0 and condition_text[0] == '!') {
            negated = true;
            condition_text = trimEnclosingParens(std.mem.trim(u8, condition_text[1..], " \t\r\n"));
        }
        const true_text = std.mem.trim(u8, text[and_idx + 2 ..], " \t\r\n");
        const condition_name = simpleStateNameText(condition_text) orelse return LowerError.InvalidTextExpression;
        const condition_sv = self.stateVar(condition_name) orelse return LowerError.UnknownStateVar;
        if (condition_sv.ty != .i1) return LowerError.InvalidTextExpression;
        const spread_branch = (try self.parseJsonObjectSpreadBranch(true_text)) orelse return LowerError.InvalidTextExpression;
        errdefer switch (spread_branch) {
            .state => {},
            .static_json => |json| self.allocator.free(json),
        };
        const noop_branch: JsonObjectSpreadBranch = .{ .static_json = try self.allocator.dupe(u8, "{}") };
        return .{
            .condition_name = condition_name,
            .true_branch = if (negated) noop_branch else spread_branch,
            .false_branch = if (negated) spread_branch else noop_branch,
        };
    }

    fn parseJsonObjectSpreadLogicalOr(self: *const SaxLowerer, expr: parser.Expr) !?JsonObjectSpreadTernary {
        const text = trimEnclosingParens(std.mem.trim(u8, expr.expr, " \t\r\n"));
        const or_idx = findTopLevelToken(text, "||") orelse return null;
        var condition_text = std.mem.trim(u8, text[0..or_idx], " \t\r\n");
        var negated = false;
        if (condition_text.len > 0 and condition_text[0] == '!') {
            negated = true;
            condition_text = trimEnclosingParens(std.mem.trim(u8, condition_text[1..], " \t\r\n"));
        }
        const false_text = std.mem.trim(u8, text[or_idx + 2 ..], " \t\r\n");
        const condition_name = simpleStateNameText(condition_text) orelse return LowerError.InvalidTextExpression;
        const condition_sv = self.stateVar(condition_name) orelse return LowerError.UnknownStateVar;
        if (condition_sv.ty != .i1) return LowerError.InvalidTextExpression;
        const spread_branch = (try self.parseJsonObjectSpreadBranch(false_text)) orelse return LowerError.InvalidTextExpression;
        errdefer switch (spread_branch) {
            .state => {},
            .static_json => |json| self.allocator.free(json),
        };
        const noop_branch: JsonObjectSpreadBranch = .{ .static_json = try self.allocator.dupe(u8, "{}") };
        return .{
            .condition_name = condition_name,
            .true_branch = if (negated) spread_branch else noop_branch,
            .false_branch = if (negated) noop_branch else spread_branch,
        };
    }

    fn parseJsonStringValueBranch(self: *const SaxLowerer, text: []const u8) !?JsonStringValueBranch {
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        if (trimmed.len == 0) return null;
        if (std.mem.eql(u8, trimmed, "null")) {
            return .{ .static_json = try self.allocator.dupe(u8, "null") };
        }
        if (trimmed[0] == '"' or trimmed[0] == '\'') {
            return .{ .static_json = try parseSimpleJsonStringKeyLiteral(self.allocator, trimmed) };
        }
        const state_name = simpleStateNameText(trimmed) orelse return null;
        const sv = self.stateVar(state_name) orelse return LowerError.UnknownStateVar;
        if (sv.ty != .ptr) return null;
        return .{ .state = state_name };
    }

    fn parseJsonStringValueTernary(self: *const SaxLowerer, expr: parser.Expr) !?JsonStringValueTernary {
        const text = trimEnclosingParens(std.mem.trim(u8, expr.expr, " \t\r\n"));
        const question = findTopLevelByte(text, '?') orelse return null;
        const colon = findTopLevelByte(text[question + 1 ..], ':') orelse return LowerError.InvalidTextExpression;
        const colon_idx = question + 1 + colon;
        const condition_text = std.mem.trim(u8, text[0..question], " \t\r\n");
        const true_text = std.mem.trim(u8, text[question + 1 .. colon_idx], " \t\r\n");
        const false_text = std.mem.trim(u8, text[colon_idx + 1 ..], " \t\r\n");
        const condition_name = simpleStateNameText(condition_text) orelse return LowerError.InvalidTextExpression;
        const condition_sv = self.stateVar(condition_name) orelse return LowerError.UnknownStateVar;
        if (condition_sv.ty != .i1) return LowerError.InvalidTextExpression;
        const true_branch = (try self.parseJsonStringValueBranch(true_text)) orelse return LowerError.InvalidTextExpression;
        errdefer switch (true_branch) {
            .state => {},
            .static_json => |json| self.allocator.free(json),
        };
        const false_branch = (try self.parseJsonStringValueBranch(false_text)) orelse return LowerError.InvalidTextExpression;
        return .{
            .condition_name = condition_name,
            .true_branch = true_branch,
            .false_branch = false_branch,
        };
    }

    fn parseJsonI64ValueBranch(self: *const SaxLowerer, text: []const u8) !?JsonI64ValueBranch {
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        if (trimmed.len == 0) return null;
        if (std.mem.eql(u8, trimmed, "null")) return null;
        if (simpleI1LiteralValue(trimmed) != null) return null;
        if (simpleStateNameText(trimmed)) |state_name| {
            const sv = self.stateVar(state_name) orelse return LowerError.UnknownStateVar;
            if (sv.ty != .i64) return null;
            return .{ .state = state_name };
        }
        if (simpleI64LiteralText(trimmed)) |literal| {
            return .{ .literal = literal };
        }
        return null;
    }

    fn parseJsonI64ValueTernary(self: *const SaxLowerer, expr: parser.Expr) !?JsonI64ValueTernary {
        const text = trimEnclosingParens(std.mem.trim(u8, expr.expr, " \t\r\n"));
        const question = findTopLevelByte(text, '?') orelse return null;
        const colon = findTopLevelByte(text[question + 1 ..], ':') orelse return LowerError.InvalidTextExpression;
        const colon_idx = question + 1 + colon;
        const condition_text = std.mem.trim(u8, text[0..question], " \t\r\n");
        const true_text = std.mem.trim(u8, text[question + 1 .. colon_idx], " \t\r\n");
        const false_text = std.mem.trim(u8, text[colon_idx + 1 ..], " \t\r\n");
        const condition_name = simpleStateNameText(condition_text) orelse return LowerError.InvalidTextExpression;
        const condition_sv = self.stateVar(condition_name) orelse return LowerError.UnknownStateVar;
        if (condition_sv.ty != .i1) return LowerError.InvalidTextExpression;
        const true_branch = (try self.parseJsonI64ValueBranch(true_text)) orelse return null;
        const false_branch = (try self.parseJsonI64ValueBranch(false_text)) orelse return null;
        return .{
            .condition_name = condition_name,
            .true_branch = true_branch,
            .false_branch = false_branch,
        };
    }

    fn parseJsonI32ValueTernary(self: *const SaxLowerer, expr: parser.Expr) !?JsonI32ValueTernary {
        const text = trimEnclosingParens(std.mem.trim(u8, expr.expr, " \t\r\n"));
        const question = findTopLevelByte(text, '?') orelse return null;
        const colon = findTopLevelByte(text[question + 1 ..], ':') orelse return LowerError.InvalidTextExpression;
        const colon_idx = question + 1 + colon;
        const condition_text = std.mem.trim(u8, text[0..question], " \t\r\n");
        const true_text = std.mem.trim(u8, text[question + 1 .. colon_idx], " \t\r\n");
        const false_text = std.mem.trim(u8, text[colon_idx + 1 ..], " \t\r\n");
        const condition_name = simpleStateNameText(condition_text) orelse return LowerError.InvalidTextExpression;
        const condition_sv = self.stateVar(condition_name) orelse return LowerError.UnknownStateVar;
        if (condition_sv.ty != .i1) return LowerError.InvalidTextExpression;
        const true_branch = (try self.parseJsonI32ValueBranch(true_text)) orelse return null;
        const false_branch = (try self.parseJsonI32ValueBranch(false_text)) orelse return null;
        return .{
            .condition_name = condition_name,
            .true_branch = true_branch,
            .false_branch = false_branch,
        };
    }

    fn parseJsonI32ValueBranch(self: *const SaxLowerer, text: []const u8) !?JsonI32ValueBranch {
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        if (trimmed.len == 0) return null;
        if (std.mem.eql(u8, trimmed, "null")) return null;
        if (simpleI1LiteralValue(trimmed) != null) return null;
        if (simpleStateNameText(trimmed)) |state_name| {
            const sv = self.stateVar(state_name) orelse return LowerError.UnknownStateVar;
            if (sv.ty != .i32) return null;
            return .{ .state = state_name };
        }
        if (simpleI32LiteralValue(trimmed)) |literal| {
            return .{ .literal = literal };
        }
        return null;
    }

    fn parseJsonF64ValueTernary(self: *const SaxLowerer, expr: parser.Expr) !?JsonF64ValueTernary {
        const text = trimEnclosingParens(std.mem.trim(u8, expr.expr, " \t\r\n"));
        const question = findTopLevelByte(text, '?') orelse return null;
        const colon = findTopLevelByte(text[question + 1 ..], ':') orelse return LowerError.InvalidTextExpression;
        const colon_idx = question + 1 + colon;
        const condition_text = std.mem.trim(u8, text[0..question], " \t\r\n");
        const true_text = std.mem.trim(u8, text[question + 1 .. colon_idx], " \t\r\n");
        const false_text = std.mem.trim(u8, text[colon_idx + 1 ..], " \t\r\n");
        const condition_name = simpleStateNameText(condition_text) orelse return LowerError.InvalidTextExpression;
        const condition_sv = self.stateVar(condition_name) orelse return LowerError.UnknownStateVar;
        if (condition_sv.ty != .i1) return LowerError.InvalidTextExpression;
        const true_branch = (try self.parseJsonF64ValueBranch(true_text)) orelse return null;
        const false_branch = (try self.parseJsonF64ValueBranch(false_text)) orelse return null;
        return .{
            .condition_name = condition_name,
            .true_branch = true_branch,
            .false_branch = false_branch,
        };
    }

    fn parseJsonF64ValueBranch(self: *const SaxLowerer, text: []const u8) !?JsonF64ValueBranch {
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        if (trimmed.len == 0) return null;
        if (std.mem.eql(u8, trimmed, "null")) return null;
        if (simpleI1LiteralValue(trimmed) != null) return null;
        if (simpleStateNameText(trimmed)) |state_name| {
            const sv = self.stateVar(state_name) orelse return LowerError.UnknownStateVar;
            if (sv.ty != .f64) return null;
            return .{ .state = state_name };
        }
        if (simpleF64LiteralBits(trimmed)) |bits| {
            return .{ .literal_bits = bits };
        }
        return null;
    }

    fn parseJsonI64TernaryKey(self: *const SaxLowerer, expr: parser.Expr) !?JsonI64TernaryKey {
        const text = trimEnclosingParens(std.mem.trim(u8, expr.expr, " \t\r\n"));
        const question = findTopLevelByte(text, '?') orelse return null;
        const colon = findTopLevelByte(text[question + 1 ..], ':') orelse return LowerError.InvalidTextExpression;
        const colon_idx = question + 1 + colon;
        const condition_text = std.mem.trim(u8, text[0..question], " \t\r\n");
        const true_text = std.mem.trim(u8, text[question + 1 .. colon_idx], " \t\r\n");
        const false_text = std.mem.trim(u8, text[colon_idx + 1 ..], " \t\r\n");
        const condition_name = simpleStateNameText(condition_text) orelse return LowerError.InvalidTextExpression;
        const condition_sv = self.stateVar(condition_name) orelse return LowerError.UnknownStateVar;
        if (condition_sv.ty != .i1) return LowerError.InvalidTextExpression;
        const true_branch = (try self.parseJsonI64ValueBranch(true_text)) orelse return null;
        const false_branch = (try self.parseJsonI64ValueBranch(false_text)) orelse return null;
        return .{
            .condition_name = condition_name,
            .true_branch = true_branch,
            .false_branch = false_branch,
        };
    }

    fn parseJsonI32TernaryKey(self: *const SaxLowerer, expr: parser.Expr) !?JsonI32TernaryKey {
        const text = trimEnclosingParens(std.mem.trim(u8, expr.expr, " \t\r\n"));
        const question = findTopLevelByte(text, '?') orelse return null;
        const colon = findTopLevelByte(text[question + 1 ..], ':') orelse return LowerError.InvalidTextExpression;
        const colon_idx = question + 1 + colon;
        const condition_text = std.mem.trim(u8, text[0..question], " \t\r\n");
        const true_text = std.mem.trim(u8, text[question + 1 .. colon_idx], " \t\r\n");
        const false_text = std.mem.trim(u8, text[colon_idx + 1 ..], " \t\r\n");
        const condition_name = simpleStateNameText(condition_text) orelse return LowerError.InvalidTextExpression;
        const condition_sv = self.stateVar(condition_name) orelse return LowerError.UnknownStateVar;
        if (condition_sv.ty != .i1) return LowerError.InvalidTextExpression;
        const true_branch = (try self.parseJsonI32ValueBranch(true_text)) orelse return null;
        const false_branch = (try self.parseJsonI32ValueBranch(false_text)) orelse return null;
        return .{
            .condition_name = condition_name,
            .true_branch = true_branch,
            .false_branch = false_branch,
        };
    }

    fn parseJsonF64TernaryKey(self: *const SaxLowerer, expr: parser.Expr) !?JsonF64TernaryKey {
        const text = trimEnclosingParens(std.mem.trim(u8, expr.expr, " \t\r\n"));
        const question = findTopLevelByte(text, '?') orelse return null;
        const colon = findTopLevelByte(text[question + 1 ..], ':') orelse return LowerError.InvalidTextExpression;
        const colon_idx = question + 1 + colon;
        const condition_text = std.mem.trim(u8, text[0..question], " \t\r\n");
        const true_text = std.mem.trim(u8, text[question + 1 .. colon_idx], " \t\r\n");
        const false_text = std.mem.trim(u8, text[colon_idx + 1 ..], " \t\r\n");
        const condition_name = simpleStateNameText(condition_text) orelse return LowerError.InvalidTextExpression;
        const condition_sv = self.stateVar(condition_name) orelse return LowerError.UnknownStateVar;
        if (condition_sv.ty != .i1) return LowerError.InvalidTextExpression;
        const true_branch = (try self.parseJsonF64ValueBranch(true_text)) orelse return null;
        const false_branch = (try self.parseJsonF64ValueBranch(false_text)) orelse return null;
        return .{
            .condition_name = condition_name,
            .true_branch = true_branch,
            .false_branch = false_branch,
        };
    }

    fn parseJsonI1TernaryKey(self: *const SaxLowerer, expr: parser.Expr) !?JsonI1TernaryKey {
        const text = trimEnclosingParens(std.mem.trim(u8, expr.expr, " \t\r\n"));
        const question = findTopLevelByte(text, '?') orelse return null;
        const colon = findTopLevelByte(text[question + 1 ..], ':') orelse return LowerError.InvalidTextExpression;
        const colon_idx = question + 1 + colon;
        const condition_text = std.mem.trim(u8, text[0..question], " \t\r\n");
        const true_text = std.mem.trim(u8, text[question + 1 .. colon_idx], " \t\r\n");
        const false_text = std.mem.trim(u8, text[colon_idx + 1 ..], " \t\r\n");
        const condition_name = simpleStateNameText(condition_text) orelse return LowerError.InvalidTextExpression;
        const condition_sv = self.stateVar(condition_name) orelse return LowerError.UnknownStateVar;
        if (condition_sv.ty != .i1) return LowerError.InvalidTextExpression;
        const true_branch = (try self.parseJsonI1ValueBranch(true_text)) orelse return null;
        const false_branch = (try self.parseJsonI1ValueBranch(false_text)) orelse return null;
        return .{
            .condition_name = condition_name,
            .true_branch = true_branch,
            .false_branch = false_branch,
        };
    }

    fn parseJsonI1ValueTernary(self: *const SaxLowerer, expr: parser.Expr) !?JsonI1ValueTernary {
        const text = trimEnclosingParens(std.mem.trim(u8, expr.expr, " \t\r\n"));
        const question = findTopLevelByte(text, '?') orelse return null;
        const colon = findTopLevelByte(text[question + 1 ..], ':') orelse return LowerError.InvalidTextExpression;
        const colon_idx = question + 1 + colon;
        const condition_text = std.mem.trim(u8, text[0..question], " \t\r\n");
        const true_text = std.mem.trim(u8, text[question + 1 .. colon_idx], " \t\r\n");
        const false_text = std.mem.trim(u8, text[colon_idx + 1 ..], " \t\r\n");
        const condition_name = simpleStateNameText(condition_text) orelse return LowerError.InvalidTextExpression;
        const condition_sv = self.stateVar(condition_name) orelse return LowerError.UnknownStateVar;
        if (condition_sv.ty != .i1) return LowerError.InvalidTextExpression;
        const true_branch = (try self.parseJsonI1ValueBranch(true_text)) orelse return null;
        const false_branch = (try self.parseJsonI1ValueBranch(false_text)) orelse return null;
        return .{
            .condition_name = condition_name,
            .true_branch = true_branch,
            .false_branch = false_branch,
        };
    }

    fn parseJsonI1ValueBranch(self: *const SaxLowerer, text: []const u8) !?JsonI1ValueBranch {
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        if (trimmed.len == 0) return null;
        if (simpleI1LiteralValue(trimmed)) |literal| {
            return .{ .literal = literal };
        }
        if (simpleStateNameText(trimmed)) |state_name| {
            const sv = self.stateVar(state_name) orelse return null;
            if (sv.ty != .i1) return null;
            return .{ .state = state_name };
        }
        return null;
    }

    fn trimEnclosingParens(text: []const u8) []const u8 {
        var current = text;
        while (current.len >= 2 and current[0] == '(' and current[current.len - 1] == ')') {
            var depth: usize = 0;
            var quote: u8 = 0;
            var escaped = false;
            var wraps = true;
            for (current, 0..) |c, idx| {
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
                if (c == '(') depth += 1;
                if (c == ')') {
                    if (depth == 0) return current;
                    depth -= 1;
                    if (depth == 0 and idx != current.len - 1) {
                        wraps = false;
                        break;
                    }
                }
            }
            if (!wraps or quote != 0 or depth != 0) return current;
            current = std.mem.trim(u8, current[1 .. current.len - 1], " \t\r\n");
        }
        return current;
    }

    fn findTopLevelByte(text: []const u8, needle: u8) ?usize {
        var quote: u8 = 0;
        var escaped = false;
        var depth: usize = 0;
        for (text, 0..) |c, idx| {
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
            if (c == '(' or c == '{' or c == '[') {
                depth += 1;
                continue;
            }
            if (c == ')' or c == '}' or c == ']') {
                if (depth == 0) return null;
                depth -= 1;
                continue;
            }
            if (depth == 0 and c == needle) return idx;
        }
        return null;
    }

    fn findTopLevelToken(text: []const u8, token: []const u8) ?usize {
        if (token.len == 0) return null;
        var quote: u8 = 0;
        var escaped = false;
        var depth: usize = 0;
        var idx: usize = 0;
        while (idx < text.len) : (idx += 1) {
            const c = text[idx];
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
            if (c == '(' or c == '{' or c == '[') {
                depth += 1;
                continue;
            }
            if (c == ')' or c == '}' or c == ']') {
                if (depth == 0) return null;
                depth -= 1;
                continue;
            }
            if (depth == 0 and std.mem.startsWith(u8, text[idx..], token)) return idx;
        }
        return null;
    }

    fn parseSimpleJsonStringKeyLiteral(allocator: Allocator, text: []const u8) ![]const u8 {
        if (text.len < 2) return LowerError.InvalidTextExpression;
        const quote = text[0];
        if ((quote != '"' and quote != '\'') or text[text.len - 1] != quote) return LowerError.InvalidTextExpression;
        const body = text[1 .. text.len - 1];
        for (body) |c| {
            if (c == quote or c == '\\' or c < 0x20) return LowerError.InvalidTextExpression;
        }
        return std.fmt.allocPrint(allocator, "\"{s}\"", .{body});
    }

    fn emitTextValue(
        self: *const SaxLowerer,
        out: *std.ArrayList(u8),
        node_name: []const u8,
        value_expr: []const u8,
        is_attr: bool,
        attr_key_idx: ?usize,
    ) !void {
        const key = if (is_attr) try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, attr_key_idx.? }) else "";
        defer if (is_attr) self.allocator.free(key);

        const buf_name = try std.fmt.allocPrint(self.allocator, "tmp_buf_{s}", .{node_name});
        defer self.allocator.free(buf_name);
        try out.writer().print("  {s} = stack_alloc 64\n", .{buf_name});
        try out.writer().print("  tmp_len_{s} = call @sax_itoa({s}, *{s}, 64)\n", .{ node_name, value_expr, buf_name });
        if (is_attr) {
            try out.writer().print("  call @sax_dom_set_attr({s}, *{s}, {}, *{s}, tmp_len_{s})\n", .{ node_name, key, self.string_pool.items.items[attr_key_idx.?].len, buf_name, node_name });
        } else {
            try out.writer().print("  call @sax_dom_set_text({s}, *{s}, tmp_len_{s})\n", .{ node_name, buf_name, node_name });
        }
    }

    fn nodeUsesValueProperty(node: parser.DomNode, attr_name: []const u8) bool {
        if (!std.mem.eql(u8, attr_name, "value")) return false;
        return std.mem.eql(u8, node.tag, "input") or
            std.mem.eql(u8, node.tag, "textarea") or
            std.mem.eql(u8, node.tag, "select");
    }

    fn nodeUsesDefaultValueProperty(node: parser.DomNode, attr_name: []const u8) bool {
        if (!std.mem.eql(u8, attr_name, "defaultValue")) return false;
        return std.mem.eql(u8, node.tag, "input") or
            std.mem.eql(u8, node.tag, "textarea") or
            std.mem.eql(u8, node.tag, "select");
    }

    fn nodeUsesDeferredDefaultValueProperty(node: parser.DomNode, attr_name: []const u8) bool {
        return std.mem.eql(u8, attr_name, "defaultValue") and std.mem.eql(u8, node.tag, "select");
    }

    fn nodeUsesCheckedProperty(node: parser.DomNode, attr_name: []const u8) bool {
        return std.mem.eql(u8, attr_name, "checked") and std.mem.eql(u8, node.tag, "input");
    }

    fn nodeUsesDefaultCheckedProperty(node: parser.DomNode, attr_name: []const u8) bool {
        return std.mem.eql(u8, attr_name, "defaultChecked") and std.mem.eql(u8, node.tag, "input");
    }

    fn isDefaultOnlyFormAttr(attr_name: []const u8) bool {
        return std.mem.eql(u8, attr_name, "defaultValue") or
            std.mem.eql(u8, attr_name, "defaultChecked") or
            std.mem.eql(u8, attr_name, "defaultSelected");
    }

    fn isRefAttr(attr_name: []const u8) bool {
        return std.mem.eql(u8, attr_name, "ref");
    }

    fn isKeyAttr(attr_name: []const u8) bool {
        return std.mem.eql(u8, attr_name, "key");
    }

    fn isDangerouslySetInnerHtmlAttr(attr_name: []const u8) bool {
        return std.mem.eql(u8, attr_name, "dangerouslySetInnerHTML");
    }

    fn isReactDomNoopAttr(attr_name: []const u8) bool {
        return std.mem.eql(u8, attr_name, "suppressContentEditableWarning") or
            std.mem.eql(u8, attr_name, "suppressHydrationWarning");
    }

    fn nodeUsesSelectedProperty(node: parser.DomNode, attr_name: []const u8) bool {
        return std.mem.eql(u8, attr_name, "selected") and std.mem.eql(u8, node.tag, "option");
    }

    fn nodeUsesDefaultSelectedProperty(node: parser.DomNode, attr_name: []const u8) bool {
        return std.mem.eql(u8, attr_name, "defaultSelected") and std.mem.eql(u8, node.tag, "option");
    }

    fn nodeUsesMultipleProperty(node: parser.DomNode, attr_name: []const u8) bool {
        return std.mem.eql(u8, attr_name, "multiple") and
            (std.mem.eql(u8, node.tag, "select") or std.mem.eql(u8, node.tag, "input"));
    }

    fn nodeUsesDisabledProperty(node: parser.DomNode, attr_name: []const u8) bool {
        if (!std.mem.eql(u8, attr_name, "disabled")) return false;
        return std.mem.eql(u8, node.tag, "button") or
            std.mem.eql(u8, node.tag, "input") or
            std.mem.eql(u8, node.tag, "select") or
            std.mem.eql(u8, node.tag, "textarea") or
            std.mem.eql(u8, node.tag, "option") or
            std.mem.eql(u8, node.tag, "optgroup") or
            std.mem.eql(u8, node.tag, "fieldset");
    }

    fn nodeUsesReadonlyProperty(node: parser.DomNode, attr_name: []const u8) bool {
        if (!std.mem.eql(u8, attr_name, "readonly")) return false;
        return std.mem.eql(u8, node.tag, "input") or std.mem.eql(u8, node.tag, "textarea");
    }

    fn nodeUsesRequiredProperty(node: parser.DomNode, attr_name: []const u8) bool {
        if (!std.mem.eql(u8, attr_name, "required")) return false;
        return std.mem.eql(u8, node.tag, "input") or
            std.mem.eql(u8, node.tag, "select") or
            std.mem.eql(u8, node.tag, "textarea");
    }

    fn nodeUsesOpenProperty(node: parser.DomNode, attr_name: []const u8) bool {
        if (!std.mem.eql(u8, attr_name, "open")) return false;
        return std.mem.eql(u8, node.tag, "dialog") or std.mem.eql(u8, node.tag, "details");
    }

    fn nodeUsesTranslateProperty(attr_name: []const u8) bool {
        return std.mem.eql(u8, attr_name, "translate");
    }

    fn nodeUsesGenericStringProperty(node: parser.DomNode, attr_name: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, attr_name, "class")) return "className";
        if (std.mem.eql(u8, attr_name, "id")) return "id";
        if (std.mem.eql(u8, attr_name, "name")) return "name";
        if (std.mem.eql(u8, attr_name, "nonce")) return "nonce";
        if (std.mem.eql(u8, attr_name, "title")) return "title";
        if (std.mem.eql(u8, attr_name, "lang")) return "lang";
        if (std.mem.eql(u8, attr_name, "dir")) return "dir";
        if (std.mem.eql(u8, attr_name, "role")) return "role";
        if (std.mem.eql(u8, attr_name, "accesskey")) return "accessKey";
        if (std.mem.eql(u8, attr_name, "tabindex")) return "tabIndex";
        if (std.mem.eql(u8, attr_name, "slot")) return "slot";
        if (std.mem.eql(u8, attr_name, "part")) return "part";
        if (std.mem.eql(u8, attr_name, "popover")) return "popover";
        if (std.mem.eql(u8, attr_name, "itemprop")) return "itemProp";
        if (std.mem.eql(u8, attr_name, "itemtype")) return "itemType";
        if (std.mem.eql(u8, attr_name, "itemid")) return "itemID";
        if (std.mem.eql(u8, attr_name, "itemref")) return "itemRef";
        if (std.mem.eql(u8, node.tag, "label") or std.mem.eql(u8, node.tag, "output")) {
            if (std.mem.eql(u8, attr_name, "for")) return "htmlFor";
        }
        if (std.mem.eql(u8, node.tag, "td") or std.mem.eql(u8, node.tag, "th")) {
            if (std.mem.eql(u8, attr_name, "rowspan")) return "rowSpan";
            if (std.mem.eql(u8, attr_name, "colspan")) return "colSpan";
            if (std.mem.eql(u8, attr_name, "headers")) return "headers";
            if (std.mem.eql(u8, attr_name, "width")) return "width";
            if (std.mem.eql(u8, attr_name, "height")) return "height";
        }
        if (std.mem.eql(u8, node.tag, "th")) {
            if (std.mem.eql(u8, attr_name, "scope")) return "scope";
            if (std.mem.eql(u8, attr_name, "abbr")) return "abbr";
        }
        if (std.mem.eql(u8, node.tag, "col") or std.mem.eql(u8, node.tag, "colgroup")) {
            if (std.mem.eql(u8, attr_name, "span")) return "span";
            if (std.mem.eql(u8, attr_name, "width")) return "width";
        }
        if (std.mem.eql(u8, node.tag, "time") or
            std.mem.eql(u8, node.tag, "del") or
            std.mem.eql(u8, node.tag, "ins"))
        {
            if (std.mem.eql(u8, attr_name, "datetime")) return "dateTime";
        }
        if (std.mem.eql(u8, node.tag, "meta")) {
            if (std.mem.eql(u8, attr_name, "charset")) return "charset";
            if (std.mem.eql(u8, attr_name, "http-equiv")) return "httpEquiv";
            if (std.mem.eql(u8, attr_name, "content")) return "content";
        }
        if (std.mem.eql(u8, node.tag, "img") or std.mem.eql(u8, node.tag, "source")) {
            if (std.mem.eql(u8, attr_name, "src")) return "src";
            if (std.mem.eql(u8, attr_name, "srcset")) return "srcset";
            if (std.mem.eql(u8, attr_name, "sizes")) return "sizes";
        }
        if (std.mem.eql(u8, node.tag, "img") or
            std.mem.eql(u8, node.tag, "video") or
            std.mem.eql(u8, node.tag, "canvas") or
            std.mem.eql(u8, node.tag, "source"))
        {
            if (std.mem.eql(u8, attr_name, "width")) return "width";
            if (std.mem.eql(u8, attr_name, "height")) return "height";
        }
        if (std.mem.eql(u8, node.tag, "img") or std.mem.eql(u8, node.tag, "area")) {
            if (std.mem.eql(u8, attr_name, "alt")) return "alt";
        }
        if (std.mem.eql(u8, node.tag, "area")) {
            if (std.mem.eql(u8, attr_name, "coords")) return "coords";
            if (std.mem.eql(u8, attr_name, "shape")) return "shape";
        }
        if (std.mem.eql(u8, node.tag, "img")) {
            if (std.mem.eql(u8, attr_name, "usemap")) return "useMap";
            if (std.mem.eql(u8, attr_name, "longdesc")) return "longDesc";
            if (std.mem.eql(u8, attr_name, "crossorigin")) return "crossOrigin";
            if (std.mem.eql(u8, attr_name, "loading")) return "loading";
            if (std.mem.eql(u8, attr_name, "decoding")) return "decoding";
            if (std.mem.eql(u8, attr_name, "fetchPriority")) return "fetchPriority";
            if (std.mem.eql(u8, attr_name, "referrerpolicy")) return "referrerPolicy";
        }
        if (std.mem.eql(u8, node.tag, "a") or std.mem.eql(u8, node.tag, "area")) {
            if (std.mem.eql(u8, attr_name, "href")) return "href";
            if (std.mem.eql(u8, node.tag, "a") and std.mem.eql(u8, attr_name, "charset")) return "charset";
            if (std.mem.eql(u8, node.tag, "a") and std.mem.eql(u8, attr_name, "coords")) return "coords";
            if (std.mem.eql(u8, node.tag, "a") and std.mem.eql(u8, attr_name, "shape")) return "shape";
            if (std.mem.eql(u8, attr_name, "hreflang")) return "hreflang";
            if (std.mem.eql(u8, attr_name, "download")) return "download";
            if (std.mem.eql(u8, attr_name, "ping")) return "ping";
            if (std.mem.eql(u8, attr_name, "rel")) return "rel";
            if (std.mem.eql(u8, node.tag, "a") and std.mem.eql(u8, attr_name, "type")) return "type";
            if (std.mem.eql(u8, attr_name, "target")) return "target";
            if (std.mem.eql(u8, attr_name, "referrerpolicy")) return "referrerPolicy";
        }
        if (std.mem.eql(u8, node.tag, "blockquote") or
            std.mem.eql(u8, node.tag, "q") or
            std.mem.eql(u8, node.tag, "del") or
            std.mem.eql(u8, node.tag, "ins"))
        {
            if (std.mem.eql(u8, attr_name, "cite")) return "cite";
        }
        if (std.mem.eql(u8, node.tag, "link")) {
            if (std.mem.eql(u8, attr_name, "href")) return "href";
            if (std.mem.eql(u8, attr_name, "hreflang")) return "hreflang";
            if (std.mem.eql(u8, attr_name, "charset")) return "charset";
            if (std.mem.eql(u8, attr_name, "rel")) return "rel";
            if (std.mem.eql(u8, attr_name, "as")) return "as";
            if (std.mem.eql(u8, attr_name, "blocking")) return "blocking";
            if (std.mem.eql(u8, attr_name, "media")) return "media";
            if (std.mem.eql(u8, attr_name, "type")) return "type";
            if (std.mem.eql(u8, attr_name, "sizes")) return "sizes";
            if (std.mem.eql(u8, attr_name, "target")) return "target";
            if (std.mem.eql(u8, attr_name, "imagesrcset")) return "imageSrcset";
            if (std.mem.eql(u8, attr_name, "imagesizes")) return "imageSizes";
            if (std.mem.eql(u8, attr_name, "integrity")) return "integrity";
            if (std.mem.eql(u8, attr_name, "fetchPriority")) return "fetchPriority";
            if (std.mem.eql(u8, attr_name, "crossorigin")) return "crossOrigin";
            if (std.mem.eql(u8, attr_name, "referrerpolicy")) return "referrerPolicy";
        }
        if (std.mem.eql(u8, node.tag, "video") or std.mem.eql(u8, node.tag, "audio")) {
            if (std.mem.eql(u8, attr_name, "src")) return "src";
            if (std.mem.eql(u8, attr_name, "preload")) return "preload";
            if (std.mem.eql(u8, attr_name, "crossorigin")) return "crossOrigin";
            if (std.mem.eql(u8, attr_name, "controlsList")) return "controlsList";
        }
        if (std.mem.eql(u8, node.tag, "video")) {
            if (std.mem.eql(u8, attr_name, "poster")) return "poster";
        }
        if (std.mem.eql(u8, node.tag, "source")) {
            if (std.mem.eql(u8, attr_name, "type")) return "type";
            if (std.mem.eql(u8, attr_name, "media")) return "media";
        }
        if (std.mem.eql(u8, node.tag, "style")) {
            if (std.mem.eql(u8, attr_name, "media")) return "media";
            if (std.mem.eql(u8, attr_name, "type")) return "type";
        }
        if (std.mem.eql(u8, node.tag, "track")) {
            if (std.mem.eql(u8, attr_name, "src")) return "src";
            if (std.mem.eql(u8, attr_name, "kind")) return "kind";
            if (std.mem.eql(u8, attr_name, "srclang")) return "srcLang";
            if (std.mem.eql(u8, attr_name, "label")) return "label";
        }
        if (std.mem.eql(u8, node.tag, "option") or std.mem.eql(u8, node.tag, "optgroup")) {
            if (std.mem.eql(u8, attr_name, "label")) return "label";
        }
        if (std.mem.eql(u8, node.tag, "option") or std.mem.eql(u8, node.tag, "button")) {
            if (std.mem.eql(u8, attr_name, "value")) return "value";
        }
        if (std.mem.eql(u8, node.tag, "input")) {
            if (std.mem.eql(u8, attr_name, "src")) return "src";
            if (std.mem.eql(u8, attr_name, "alt")) return "alt";
            if (std.mem.eql(u8, attr_name, "width")) return "width";
            if (std.mem.eql(u8, attr_name, "height")) return "height";
            if (std.mem.eql(u8, attr_name, "min")) return "min";
            if (std.mem.eql(u8, attr_name, "max")) return "max";
            if (std.mem.eql(u8, attr_name, "step")) return "step";
            if (std.mem.eql(u8, attr_name, "size")) return "size";
            if (std.mem.eql(u8, attr_name, "placeholder")) return "placeholder";
            if (std.mem.eql(u8, attr_name, "pattern")) return "pattern";
            if (std.mem.eql(u8, attr_name, "accept")) return "accept";
            if (std.mem.eql(u8, attr_name, "capture")) return "capture";
            if (std.mem.eql(u8, attr_name, "dirname")) return "dirName";
            if (std.mem.eql(u8, attr_name, "maxlength")) return "maxLength";
            if (std.mem.eql(u8, attr_name, "minlength")) return "minLength";
            if (std.mem.eql(u8, attr_name, "autocomplete")) return "autocomplete";
        }
        if (std.mem.eql(u8, node.tag, "form")) {
            if (std.mem.eql(u8, attr_name, "action")) return "action";
            if (std.mem.eql(u8, attr_name, "autocomplete")) return "autocomplete";
            if (std.mem.eql(u8, attr_name, "accept-charset")) return "acceptCharset";
            if (std.mem.eql(u8, attr_name, "enctype")) return "enctype";
            if (std.mem.eql(u8, attr_name, "method")) return "method";
            if (std.mem.eql(u8, attr_name, "rel")) return "rel";
            if (std.mem.eql(u8, attr_name, "target")) return "target";
        }
        if (std.mem.eql(u8, node.tag, "base")) {
            if (std.mem.eql(u8, attr_name, "href")) return "href";
            if (std.mem.eql(u8, attr_name, "target")) return "target";
        }
        if (std.mem.eql(u8, node.tag, "button") or std.mem.eql(u8, node.tag, "input")) {
            if (std.mem.eql(u8, attr_name, "type")) return "type";
            if (std.mem.eql(u8, attr_name, "formaction")) return "formAction";
            if (std.mem.eql(u8, attr_name, "formenctype")) return "formEnctype";
            if (std.mem.eql(u8, attr_name, "formmethod")) return "formMethod";
            if (std.mem.eql(u8, attr_name, "formtarget")) return "formTarget";
        }
        if (std.mem.eql(u8, node.tag, "textarea")) {
            if (std.mem.eql(u8, attr_name, "rows")) return "rows";
            if (std.mem.eql(u8, attr_name, "cols")) return "cols";
            if (std.mem.eql(u8, attr_name, "wrap")) return "wrap";
            if (std.mem.eql(u8, attr_name, "placeholder")) return "placeholder";
            if (std.mem.eql(u8, attr_name, "dirname")) return "dirName";
            if (std.mem.eql(u8, attr_name, "maxlength")) return "maxLength";
            if (std.mem.eql(u8, attr_name, "minlength")) return "minLength";
            if (std.mem.eql(u8, attr_name, "autocomplete")) return "autocomplete";
        }
        if (std.mem.eql(u8, node.tag, "select")) {
            if (std.mem.eql(u8, attr_name, "size")) return "size";
            if (std.mem.eql(u8, attr_name, "autocomplete")) return "autocomplete";
        }
        if (std.mem.eql(u8, node.tag, "ol")) {
            if (std.mem.eql(u8, attr_name, "start")) return "start";
            if (std.mem.eql(u8, attr_name, "type")) return "type";
        }
        if (std.mem.eql(u8, node.tag, "li")) {
            if (std.mem.eql(u8, attr_name, "value")) return "value";
        }
        if (std.mem.eql(u8, node.tag, "data")) {
            if (std.mem.eql(u8, attr_name, "value")) return "value";
        }
        if (std.mem.eql(u8, node.tag, "param")) {
            if (std.mem.eql(u8, attr_name, "value")) return "value";
        }
        if (std.mem.eql(u8, node.tag, "meter")) {
            if (std.mem.eql(u8, attr_name, "value")) return "value";
            if (std.mem.eql(u8, attr_name, "min")) return "min";
            if (std.mem.eql(u8, attr_name, "max")) return "max";
            if (std.mem.eql(u8, attr_name, "low")) return "low";
            if (std.mem.eql(u8, attr_name, "high")) return "high";
            if (std.mem.eql(u8, attr_name, "optimum")) return "optimum";
        }
        if (std.mem.eql(u8, node.tag, "progress")) {
            if (std.mem.eql(u8, attr_name, "value")) return "value";
            if (std.mem.eql(u8, attr_name, "max")) return "max";
        }
        if (std.mem.eql(u8, attr_name, "inputmode")) return "inputMode";
        if (std.mem.eql(u8, attr_name, "enterkeyhint")) return "enterKeyHint";
        if (std.mem.eql(u8, attr_name, "autocapitalize")) return "autoCapitalize";
        if (std.mem.eql(u8, attr_name, "autocorrect")) return "autocorrect";
        if (std.mem.eql(u8, attr_name, "contenteditable")) return "contentEditable";
        if (std.mem.eql(u8, attr_name, "spellcheck")) return "spellcheck";
        return null;
    }

    fn nodeUsesAutofocusProperty(attr_name: []const u8) bool {
        return std.mem.eql(u8, attr_name, "autofocus");
    }

    fn nodeHasAttr(node: parser.DomNode, attr_name: []const u8) bool {
        for (node.attrs) |attr| {
            if (std.mem.eql(u8, attr.name, attr_name)) return true;
        }
        return false;
    }

    fn literalBoolValue(text: []const u8) ?bool {
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        if (trimmed.len == 0) return null;
        if (std.mem.eql(u8, trimmed, "1") or
            std.mem.eql(u8, trimmed, "true") or
            std.mem.eql(u8, trimmed, "checked")) return true;
        if (std.mem.eql(u8, trimmed, "0") or
            std.mem.eql(u8, trimmed, "false")) return false;
        return null;
    }

    fn emitTextPieceBuffer(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        node: parser.DomNode,
        node_var: []const u8,
    ) !void {
        if (separateTextNodeCount(node) != 0) return;
        const is_textarea = std.mem.eql(u8, node.tag, "textarea");
        if (nodeHasAttr(node, "dangerouslySetInnerHTML")) return;
        const textarea_has_value_attr = nodeHasAttr(node, "value") or nodeHasAttr(node, "defaultValue");
        if (is_textarea and textarea_has_value_attr) return;
        const textarea_children_as_value = is_textarea;
        var has_text = false;
        for (node.children) |child| {
            switch (child) {
                .text => |piece| switch (piece) {
                    .text, .interpolation => {
                        has_text = true;
                        break;
                    },
                    .json_string_interpolation => return LowerError.InvalidTextExpression,
                    .json_object_spread => return LowerError.InvalidTextExpression,
                },
                else => {},
            }
        }
        if (!has_text) return;

        const buf_size = @max(self.nodeTextBufferSize(node), 32);
        const buf_name = try std.fmt.allocPrint(self.allocator, "text_buf_{s}", .{node.alias});
        defer self.allocator.free(buf_name);
        const cursor_name = try std.fmt.allocPrint(self.allocator, "text_len_{s}", .{node.alias});
        defer self.allocator.free(cursor_name);

        try out.writer().print("  {s} = stack_alloc {}\n", .{ buf_name, buf_size });
        try out.writer().print("  {s} = 0\n", .{cursor_name});

        var piece_index: usize = 0;
        for (node.children) |child| {
            switch (child) {
                .text => |piece| switch (piece) {
                    .text => |txt| {
                        const text_idx = try self.string_pool.add(txt);
                        const text_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, text_idx });
                        defer self.allocator.free(text_const);
                        const dst_name = try std.fmt.allocPrint(self.allocator, "text_dst_{s}_{d}", .{ node.alias, piece_index });
                        defer self.allocator.free(dst_name);
                        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, cursor_name });
                        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, {})\n", .{ dst_name, text_const, txt.len });
                        try out.writer().print("  {s} = add {s}, {}\n", .{ cursor_name, cursor_name, txt.len });
                    },
                    .interpolation => |expr| {
                        if (simpleStateExprName(expr)) |name| {
                            if (self.stateVar(name)) |sv| {
                                if (sv.ty == .ptr) {
                                    const slice_prefix = try std.fmt.allocPrint(self.allocator, "text_{s}_{d}", .{ node.alias, piece_index });
                                    defer self.allocator.free(slice_prefix);
                                    const slice = try self.emitLoadStateStringSlice(out, name, slice_prefix);
                                    defer self.allocator.free(slice.ptr_name);
                                    defer self.allocator.free(slice.len_name);
                                    const dst_name = try std.fmt.allocPrint(self.allocator, "text_dst_{s}_{d}", .{ node.alias, piece_index });
                                    defer self.allocator.free(dst_name);
                                    try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, cursor_name });
                                    try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, {s})\n", .{ dst_name, slice.ptr_name, slice.len_name });
                                    try out.writer().print("  {s} = add {s}, {s}\n", .{ cursor_name, cursor_name, slice.len_name });
                                    continue;
                                }
                            }
                        }
                        var expr_arena = std.heap.ArenaAllocator.init(self.allocator);
                        defer expr_arena.deinit();
                        const expr_prefix = try std.fmt.allocPrint(self.allocator, "text_expr_{s}_{d}", .{ node.alias, piece_index });
                        defer self.allocator.free(expr_prefix);
                        const value = try self.emitInterpolationExpr(out, expr, expr_prefix, expr_arena.allocator());
                        const tmp_buf_name = try std.fmt.allocPrint(self.allocator, "text_tmp_{s}_{d}", .{ node.alias, piece_index });
                        defer self.allocator.free(tmp_buf_name);
                        const tmp_len_name = try std.fmt.allocPrint(self.allocator, "text_tmp_len_{s}_{d}", .{ node.alias, piece_index });
                        defer self.allocator.free(tmp_len_name);
                        const dst_name = try std.fmt.allocPrint(self.allocator, "text_dst_{s}_{d}", .{ node.alias, piece_index });
                        defer self.allocator.free(dst_name);
                        try out.writer().print("  {s} = stack_alloc 64\n", .{tmp_buf_name});
                        try self.emitFormatInterpolationValue(out, value, tmp_buf_name, tmp_len_name);
                        try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst_name, buf_name, cursor_name });
                        try out.writer().print("  call @sax_mem_copy(*{s}, *{s}, {s})\n", .{ dst_name, tmp_buf_name, tmp_len_name });
                        try out.writer().print("  {s} = add {s}, {s}\n", .{ cursor_name, cursor_name, tmp_len_name });
                    },
                    .json_string_interpolation => return LowerError.InvalidTextExpression,
                    .json_object_spread => return LowerError.InvalidTextExpression,
                },
                else => {},
            }
            piece_index += 1;
        }

        if (textarea_children_as_value) {
            try out.writer().print("  call @sax_dom_set_value({s}, *{s}, {s})\n", .{ node_var, buf_name, cursor_name });
        } else {
            try out.writer().print("  call @sax_dom_set_text({s}, *{s}, {s})\n", .{ node_var, buf_name, cursor_name });
        }
    }

    fn emitNodeAttrs(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        node: parser.DomNode,
        node_var: []const u8,
        ctx_var: []const u8,
        bind_events: bool,
        initial_write: bool,
    ) !void {
        for (node.attrs, 0..) |attr, idx| {
            if (attr.is_event) {
                if (!bind_events) continue;
                const handler_name = attr.event_handler orelse return LowerError.UnknownHandler;
                if (self.event_handlers.get(handler_name) == null) return LowerError.UnknownHandler;

                const event_name = domEventName(node, attr.name);
                const evt_idx = try self.string_pool.add(event_name);
                const evt_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, evt_idx });
                defer self.allocator.free(evt_const);
                const handler_export = try self.handlerExportName(handler_name);
                defer self.allocator.free(handler_export);
                const handler_idx = try self.string_pool.add(handler_export);
                const handler_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, handler_idx });
                defer self.allocator.free(handler_const);
                const bind_fn = if (isCaptureEventAttr(attr.name)) "sax_dom_bind_event_capture" else "sax_dom_bind_event";
                try out.writer().print("  call @{s}({s}, *{s}, {}, *{s}, {}, {s})\n", .{ bind_fn, node_var, evt_const, event_name.len, handler_const, handler_export.len, ctx_var });
                continue;
            }
            if (isRefAttr(attr.name) or isKeyAttr(attr.name) or isReactDomNoopAttr(attr.name)) continue;
            if (std.mem.eql(u8, node.tag, "Slot") and (std.mem.eql(u8, attr.name, "contextProps") or std.mem.eql(u8, attr.name, "contextScope"))) continue;
            if (isDangerouslySetInnerHtmlAttr(attr.name)) {
                switch (attr.value) {
                    .literal => |lit| {
                        const html_idx = try self.string_pool.add(lit);
                        const html_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, html_idx });
                        defer self.allocator.free(html_const);
                        try out.writer().print("  call @sax_dom_set_inner_html({s}, *{s}, {})\n", .{ node_var, html_const, lit.len });
                    },
                    else => return LowerError.InvalidInterpolation,
                }
                continue;
            }
            if (!initial_write and isDefaultOnlyFormAttr(attr.name)) continue;
            if (initial_write and nodeUsesDeferredDefaultValueProperty(node, attr.name)) continue;

            const use_value_property = nodeUsesValueProperty(node, attr.name);
            const use_default_value_property = initial_write and nodeUsesDefaultValueProperty(node, attr.name);
            const use_checked_property = nodeUsesCheckedProperty(node, attr.name);
            const use_default_checked_property = initial_write and nodeUsesDefaultCheckedProperty(node, attr.name);
            const use_selected_property = nodeUsesSelectedProperty(node, attr.name);
            const use_default_selected_property = initial_write and nodeUsesDefaultSelectedProperty(node, attr.name);
            const use_multiple_property = nodeUsesMultipleProperty(node, attr.name);
            const use_disabled_property = nodeUsesDisabledProperty(node, attr.name);
            const use_readonly_property = nodeUsesReadonlyProperty(node, attr.name);
            const use_required_property = nodeUsesRequiredProperty(node, attr.name);
            const use_open_property = nodeUsesOpenProperty(node, attr.name);
            const use_translate_property = nodeUsesTranslateProperty(attr.name);
            const generic_bool_prop = nodeUsesGenericBoolProperty(node, attr.name);
            const generic_string_prop = nodeUsesGenericStringProperty(node, attr.name);
            switch (attr.value) {
                .literal => |lit| {
                    if (use_checked_property or use_default_checked_property) {
                        const checked = literalBoolValue(lit) orelse true;
                        try out.writer().print("  call @sax_dom_set_checked({s}, {s})\n", .{ node_var, if (checked) "1" else "0" });
                        continue;
                    }
                    if (use_selected_property or use_default_selected_property) {
                        const selected = literalBoolValue(lit) orelse true;
                        try out.writer().print("  call @sax_dom_set_selected({s}, {s})\n", .{ node_var, if (selected) "1" else "0" });
                        continue;
                    }
                    if (use_multiple_property) {
                        const multiple = literalBoolValue(lit) orelse true;
                        try out.writer().print("  call @sax_dom_set_multiple({s}, {s})\n", .{ node_var, if (multiple) "1" else "0" });
                        continue;
                    }
                    if (use_disabled_property) {
                        const disabled = literalBoolValue(lit) orelse true;
                        try out.writer().print("  call @sax_dom_set_disabled({s}, {s})\n", .{ node_var, if (disabled) "1" else "0" });
                        continue;
                    }
                    if (use_readonly_property) {
                        const readonly = literalBoolValue(lit) orelse true;
                        try out.writer().print("  call @sax_dom_set_readonly({s}, {s})\n", .{ node_var, if (readonly) "1" else "0" });
                        continue;
                    }
                    if (use_required_property) {
                        const required = literalBoolValue(lit) orelse true;
                        try out.writer().print("  call @sax_dom_set_required({s}, {s})\n", .{ node_var, if (required) "1" else "0" });
                        continue;
                    }
                    if (use_open_property) {
                        const open = literalBoolValue(lit) orelse true;
                        try out.writer().print("  call @sax_dom_set_open({s}, {s})\n", .{ node_var, if (open) "1" else "0" });
                        continue;
                    }
                    if (generic_bool_prop) |prop_name| {
                        const value = literalBoolValue(lit) orelse true;
                        try self.emitLiteralGenericBoolProperty(out, node_var, prop_name, value);
                        continue;
                    }
                    if (use_value_property or use_default_value_property) {
                        const val_idx = try self.string_pool.add(lit);
                        const val_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, val_idx });
                        defer self.allocator.free(val_const);
                        try out.writer().print("  call @sax_dom_set_value({s}, *{s}, {})\n", .{ node_var, val_const, lit.len });
                        continue;
                    }
                    if (use_translate_property) {
                        try self.emitLiteralTranslateProperty(out, node_var, lit);
                        continue;
                    }
                    if (generic_string_prop) |prop_name| {
                        try self.emitLiteralGenericStringProperty(out, node_var, prop_name, lit);
                        continue;
                    }
                    const key_idx = try self.string_pool.add(attr.name);
                    const val_idx = try self.string_pool.add(lit);
                    const key_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, key_idx });
                    defer self.allocator.free(key_const);
                    const val_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, val_idx });
                    defer self.allocator.free(val_const);
                    try out.writer().print("  call @sax_dom_set_attr({s}, *{s}, {}, *{s}, {})\n", .{ node_var, key_const, attr.name.len, val_const, lit.len });
                },
                .interpolation => |expr| {
                    if (use_checked_property or use_default_checked_property) {
                        try self.emitInterpolatedBoolProperty(out, node_var, attr.name, "checked", "sax_dom_set_checked", expr);
                        continue;
                    }
                    if (use_selected_property or use_default_selected_property) {
                        try self.emitInterpolatedBoolProperty(out, node_var, attr.name, "selected", "sax_dom_set_selected", expr);
                        continue;
                    }
                    if (use_multiple_property) {
                        try self.emitInterpolatedBoolProperty(out, node_var, attr.name, "multiple", "sax_dom_set_multiple", expr);
                        continue;
                    }
                    if (use_disabled_property) {
                        try self.emitInterpolatedBoolProperty(out, node_var, attr.name, "disabled", "sax_dom_set_disabled", expr);
                        continue;
                    }
                    if (use_readonly_property) {
                        try self.emitInterpolatedBoolProperty(out, node_var, attr.name, "readonly", "sax_dom_set_readonly", expr);
                        continue;
                    }
                    if (use_required_property) {
                        try self.emitInterpolatedBoolProperty(out, node_var, attr.name, "required", "sax_dom_set_required", expr);
                        continue;
                    }
                    if (use_open_property) {
                        try self.emitInterpolatedBoolProperty(out, node_var, attr.name, "open", "sax_dom_set_open", expr);
                        continue;
                    }
                    if (generic_bool_prop) |prop_name| {
                        try self.emitInterpolatedGenericBoolProperty(out, node_var, attr.name, prop_name, expr);
                        continue;
                    }
                    if (use_translate_property) {
                        try self.emitInterpolatedTranslateProperty(out, node_var, attr.name, expr);
                        continue;
                    }
                    if (generic_string_prop) |prop_name| {
                        try self.emitInterpolatedGenericStringProperty(out, node_var, attr.name, prop_name, expr);
                        continue;
                    }
                    try self.emitInterpolatedValue(out, node_var, attr.name, expr, true, use_value_property or use_default_value_property);
                },
                .template => |pieces| {
                    const prefix = try std.fmt.allocPrint(self.allocator, "attr_tpl_{s}_{s}", .{ node_var, attr.name });
                    defer self.allocator.free(prefix);
                    const slice = try self.emitTemplateBuffer(out, pieces, prefix);
                    defer self.allocator.free(slice.ptr_name);
                    defer self.allocator.free(slice.len_name);
                    if (use_value_property or use_default_value_property) {
                        try out.writer().print("  call @sax_dom_set_value({s}, *{s}, {s})\n", .{ node_var, slice.ptr_name, slice.len_name });
                        continue;
                    }
                    if (use_translate_property) {
                        try self.emitTranslatePropertySlice(out, node_var, slice.ptr_name, slice.len_name);
                        continue;
                    }
                    if (generic_string_prop) |prop_name| {
                        try self.emitGenericStringPropertySlice(out, node_var, prop_name, slice.ptr_name, slice.len_name);
                        continue;
                    }
                    const key_idx = try self.string_pool.add(attr.name);
                    const key_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, key_idx });
                    defer self.allocator.free(key_const);
                    try out.writer().print("  call @sax_dom_set_attr({s}, *{s}, {}, *{s}, {s})\n", .{
                        node_var,
                        key_const,
                        attr.name.len,
                        slice.ptr_name,
                        slice.len_name,
                    });
                },
            }
            _ = idx;
        }
    }

    fn nodeCreateTag(node: parser.DomNode) []const u8 {
        if (std.mem.eql(u8, node.tag, "Slot")) return "slot";
        if (std.mem.eql(u8, node.tag, "Fragment") or std.mem.eql(u8, node.tag, "React.Fragment")) return "fragment";
        return node.tag;
    }

    fn emitNodeInit(self: *SaxLowerer, out: *std.ArrayList(u8), ctx_var: []const u8, idx: usize) !void {
        const node = self.component.dom_nodes[idx];
        if (node.is_user_component) return;
        const slot = self.node_slots[idx];
        const node_var = try std.fmt.allocPrint(self.allocator, "node_{d}", .{idx});
        defer self.allocator.free(node_var);

        const tag_text = nodeCreateTag(node);
        const tag_idx = if (std.mem.eql(u8, tag_text, node.tag)) slot.tag_const else try self.string_pool.add(tag_text);
        const tag_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, tag_idx });
        defer self.allocator.free(tag_const);
        try out.writer().print("  {s} = call @sax_dom_create(*{s}, {})\n", .{ node_var, tag_const, tag_text.len });
        const node_slot = try self.nodeSlotConstName(node.alias);
        defer self.allocator.free(node_slot);
        try out.writer().print("  store dom+{s}, {s} as i64\n", .{ node_slot, node_var });

        try self.emitNodeAttrs(out, node, node_var, ctx_var, true, true);
        try self.emitNodeRefs(out, node, node_var, ctx_var);
        try self.emitSeparateTextNodeInits(out, node, slot);
    }

    fn emitSeparateTextNodeInits(self: *SaxLowerer, out: *std.ArrayList(u8), node: parser.DomNode, slot: NodeSlots) !void {
        if (slot.text_slot_count == 0) return;
        _ = slot.text_slot_start orelse return;
        var text_idx: usize = 0;
        var child_order: usize = 0;
        for (node.children) |child| {
            defer child_order += 1;
            const piece = switch (child) {
                .text => |piece| piece,
                .node_index => continue,
            };
            if (!textPieceNeedsSeparateNode(piece)) continue;
            const text_var = try std.fmt.allocPrint(self.allocator, "text_node_{s}_{d}", .{ node.alias, text_idx });
            defer self.allocator.free(text_var);
            const prefix = try std.fmt.allocPrint(self.allocator, "text_node_{s}_{d}_{d}", .{ node.alias, text_idx, child_order });
            defer self.allocator.free(prefix);
            const emitted = try self.emitTextPieceWrite(out, piece, text_var, prefix, true);
            if (!emitted) continue;
            const text_slot_name = try self.textNodeSlotConstName(node.alias, text_idx);
            defer self.allocator.free(text_slot_name);
            try out.writer().print("  store dom+{s}, {s} as i64\n", .{ text_slot_name, text_var });
            text_idx += 1;
        }
    }

    fn emitNodeRefs(self: *SaxLowerer, out: *std.ArrayList(u8), node: parser.DomNode, node_var: []const u8, ctx_var: []const u8) !void {
        for (node.attrs) |attr| {
            if (!isRefAttr(attr.name)) continue;
            const expr = switch (attr.value) {
                .interpolation => |expr| expr,
                else => return LowerError.InvalidInterpolation,
            };
            const ref_state_name = simpleStateExprName(expr) orelse return LowerError.InvalidInterpolation;
            const ref_state = self.stateVar(ref_state_name) orelse {
                if (try self.refCallbackHandlerName(attr)) |handler_name| {
                    try self.emitRefCallbackCall(out, handler_name, .dom, ctx_var, node_var);
                    continue;
                }
                return LowerError.UnknownStateVar;
            };
            if (ref_state.ty != .i64) return LowerError.InvalidInterpolation;
            const slot_name = try self.stateSlotConstName(ref_state_name);
            defer self.allocator.free(slot_name);
            try out.writer().print("  store state+{s}, {s} as i64\n", .{ slot_name, node_var });
        }
    }

    fn emitUserComponentRef(self: *SaxLowerer, out: *std.ArrayList(u8), node: parser.DomNode, ctx_var: []const u8, owner_ctx_var: []const u8) !void {
        for (node.attrs) |attr| {
            if (!isRefAttr(attr.name)) continue;
            const expr = switch (attr.value) {
                .interpolation => |expr| expr,
                else => return LowerError.InvalidInterpolation,
            };
            const ref_state_name = simpleStateExprName(expr) orelse return LowerError.InvalidInterpolation;
            const ref_state = self.stateVar(ref_state_name) orelse {
                if (try self.refCallbackHandlerName(attr)) |handler_name| {
                    try self.emitRefCallbackCall(out, handler_name, .component, owner_ctx_var, ctx_var);
                    continue;
                }
                return LowerError.UnknownStateVar;
            };
            if (ref_state.ty != .ptr) return LowerError.InvalidInterpolation;
            const slot_name = try self.stateSlotConstName(ref_state_name);
            defer self.allocator.free(slot_name);
            try out.writer().print("  store state+{s}, {s} as ptr\n", .{ slot_name, ctx_var });
        }
    }

    fn literalIsInteger(text: []const u8) bool {
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        if (trimmed.len == 0) return false;
        var idx: usize = if (trimmed[0] == '-') 1 else 0;
        if (idx >= trimmed.len) return false;
        while (idx < trimmed.len) : (idx += 1) {
            if (!std.ascii.isDigit(trimmed[idx])) return false;
        }
        return true;
    }

    fn emitUserComponentStaticStringTernaryProp(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        node: parser.DomNode,
        ctx_var: []const u8,
        target_prop_name: []const u8,
        ternary: StaticStringTernary,
        attr_idx: usize,
    ) !void {
        const setter = try self.componentStringStateSetterName(node.tag, target_prop_name);
        defer self.allocator.free(setter);
        const prefix = try std.fmt.allocPrint(self.allocator, "prop_str_ternary_{s}_{d}", .{ node.alias, attr_idx });
        defer self.allocator.free(prefix);
        const buf_name = try std.fmt.allocPrint(self.allocator, "{s}_buf", .{prefix});
        defer self.allocator.free(buf_name);
        const len_name = try std.fmt.allocPrint(self.allocator, "{s}_len", .{prefix});
        defer self.allocator.free(len_name);
        try out.writer().print("  {s} = stack_alloc {}\n", .{ buf_name, @max(@max(ternary.true_text.len, ternary.false_text.len), 1) });
        try out.writer().print("  {s} = 0\n", .{len_name});
        try self.emitStaticStringTernaryCopy(out, ternary, buf_name, len_name, prefix, 0);
        try out.writer().print("  call @{s}({s}, *{s}, {s})\n", .{ setter, ctx_var, buf_name, len_name });
    }

    fn pascalizeObjectKey(self: *SaxLowerer, key: []const u8) ![]u8 {
        var out = std.ArrayList(u8).init(self.allocator);
        errdefer out.deinit();

        var uppercase_next = true;
        for (key) |c| {
            if (!std.ascii.isAlphanumeric(c)) {
                uppercase_next = true;
                continue;
            }
            if (uppercase_next) {
                try out.append(std.ascii.toUpper(c));
                uppercase_next = false;
            } else {
                try out.append(c);
            }
        }

        return out.toOwnedSlice();
    }

    fn projectedObjectStateName(self: *SaxLowerer, prefix: []const u8, key: []const u8, suffix: []const u8) ![]u8 {
        const pascal_key = try self.pascalizeObjectKey(key);
        defer self.allocator.free(pascal_key);
        return try std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{ prefix, pascal_key, suffix });
    }

    fn emitUserComponentStringStateLiteral(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        node: parser.DomNode,
        ctx_var: []const u8,
        state_name: []const u8,
        value: []const u8,
    ) !bool {
        const target_state = self.componentStateVar(node.tag, state_name) orelse return false;
        if (target_state.ty != .ptr) return false;

        const setter = try self.componentStringStateSetterName(node.tag, state_name);
        defer self.allocator.free(setter);
        const value_idx = try self.string_pool.add(value);
        const value_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, value_idx });
        defer self.allocator.free(value_const);
        try out.writer().print("  call @{s}({s}, *{s}, {})\n", .{ setter, ctx_var, value_const, value.len });
        return true;
    }

    fn emitMuiClassesObjectProp(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        node: parser.DomNode,
        ctx_var: []const u8,
        literal: []const u8,
    ) !bool {
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, literal, .{}) catch return false;
        defer parsed.deinit();

        const object = switch (parsed.value) {
            .object => |obj| obj,
            else => return false,
        };

        var emitted = false;
        var it = object.iterator();
        while (it.next()) |entry| {
            const class_name = switch (entry.value_ptr.*) {
                .string => |value| value,
                else => continue,
            };

            const state_name = try self.projectedObjectStateName("classes", entry.key_ptr.*, "");
            defer self.allocator.free(state_name);
            if (try self.emitUserComponentStringStateLiteral(out, node, ctx_var, state_name, class_name)) {
                emitted = true;
                continue;
            }

            if (std.mem.eql(u8, entry.key_ptr.*, "root")) {
                if (try self.emitUserComponentStringStateLiteral(out, node, ctx_var, "className", class_name)) {
                    emitted = true;
                }
            }
        }

        return emitted;
    }

    fn emitMuiSlotPropsObjectProp(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        node: parser.DomNode,
        ctx_var: []const u8,
        literal: []const u8,
    ) !bool {
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, literal, .{}) catch return false;
        defer parsed.deinit();

        const object = switch (parsed.value) {
            .object => |obj| obj,
            else => return false,
        };

        var emitted = false;
        var it = object.iterator();
        while (it.next()) |entry| {
            const slot_object = switch (entry.value_ptr.*) {
                .object => |obj| obj,
                else => continue,
            };
            const class_value = switch (slot_object.get("className") orelse continue) {
                .string => |value| value,
                else => continue,
            };

            const state_name = try self.projectedObjectStateName("slotProps", entry.key_ptr.*, "ClassName");
            defer self.allocator.free(state_name);
            if (try self.emitUserComponentStringStateLiteral(out, node, ctx_var, state_name, class_value)) {
                emitted = true;
                continue;
            }

            if (std.mem.eql(u8, entry.key_ptr.*, "root")) {
                if (try self.emitUserComponentStringStateLiteral(out, node, ctx_var, "className", class_value)) {
                    emitted = true;
                }
            }
        }

        return emitted;
    }

    fn emitMuiObjectPropProjection(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        node: parser.DomNode,
        ctx_var: []const u8,
        attr: parser.Attribute,
    ) !bool {
        if (!attr.is_object_prop) return false;
        const literal = switch (attr.value) {
            .literal => |lit| lit,
            else => return false,
        };
        if (std.mem.eql(u8, attr.name, "classes")) {
            return try self.emitMuiClassesObjectProp(out, node, ctx_var, literal);
        }
        if (std.mem.eql(u8, attr.name, "slotProps") or std.mem.eql(u8, attr.name, "componentsProps")) {
            return try self.emitMuiSlotPropsObjectProp(out, node, ctx_var, literal);
        }
        return false;
    }

    fn emitUserComponentProps(self: *SaxLowerer, out: *std.ArrayList(u8), node: parser.DomNode, ctx_var: []const u8) !void {
        for (node.attrs, 0..) |attr, idx| {
            if (attr.is_event) continue;
            if (isRefAttr(attr.name) or isKeyAttr(attr.name)) continue;
            const projected_object_prop = try self.emitMuiObjectPropProjection(out, node, ctx_var, attr);
            const target_prop = self.componentStateProp(node.tag, attr.name) orelse {
                if (projected_object_prop) continue;
                continue;
            };
            const target_state = target_prop.state;
            switch (attr.value) {
                .literal => |lit| {
                    if (target_state.ty == .ptr) {
                        const setter = try self.componentStringStateSetterName(node.tag, target_prop.name);
                        defer self.allocator.free(setter);
                        const value_idx = try self.string_pool.add(lit);
                        const value_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, value_idx });
                        defer self.allocator.free(value_const);
                        if (attr.is_object_prop) {
                            const value_len = try std.fmt.allocPrint(self.allocator, "{}", .{lit.len});
                            defer self.allocator.free(value_len);
                            const source: StateStringSlice = .{ .ptr_name = value_const, .len_name = value_len };
                            const prefix = try std.fmt.allocPrint(self.allocator, "prop_obj_{s}_{d}", .{ node.alias, idx });
                            defer self.allocator.free(prefix);
                            const normalized = try self.emitJsonNormalizeObjectBuffer(out, source, prefix, lit.len);
                            defer self.allocator.free(normalized.ptr_name);
                            defer self.allocator.free(normalized.len_name);
                            try out.writer().print("  call @{s}({s}, *{s}, {s})\n", .{ setter, ctx_var, normalized.ptr_name, normalized.len_name });
                        } else {
                            try out.writer().print("  call @{s}({s}, *{s}, {})\n", .{ setter, ctx_var, value_const, lit.len });
                        }
                        continue;
                    }
                    if (!literalIsInteger(lit)) continue;
                    const setter = try self.componentStateSetterName(node.tag, target_prop.name);
                    defer self.allocator.free(setter);
                    try out.writer().print("  call @{s}({s}, {s})\n", .{ setter, ctx_var, std.mem.trim(u8, lit, " \t\r\n") });
                },
                .interpolation => |expr| {
                    if (target_state.ty == .ptr) {
                        if (simpleStateExprName(expr)) |source_state_name| {
                            const source_state = self.stateVar(source_state_name) orelse continue;
                            if (source_state.ty != .ptr) continue;
                            const setter = try self.componentStringStateSetterName(node.tag, target_prop.name);
                            defer self.allocator.free(setter);
                            const prefix = try std.fmt.allocPrint(self.allocator, "prop_str_{s}_{d}", .{ node.alias, idx });
                            defer self.allocator.free(prefix);
                            const slice = try self.emitLoadStateStringSlice(out, source_state_name, prefix);
                            defer self.allocator.free(slice.ptr_name);
                            defer self.allocator.free(slice.len_name);
                            try out.writer().print("  call @{s}({s}, *{s}, {s})\n", .{ setter, ctx_var, slice.ptr_name, slice.len_name });
                            continue;
                        }
                        if (self.parseStaticStringTernary(expr)) |ternary| {
                            try self.emitUserComponentStaticStringTernaryProp(out, node, ctx_var, target_prop.name, ternary, idx);
                            continue;
                        }
                        continue;
                    }
                    if (target_state.ty == .i1) {
                        if (simpleI1LiteralValue(expr.expr)) |bool_value| {
                            const setter = try self.componentStateSetterName(node.tag, target_prop.name);
                            defer self.allocator.free(setter);
                            try out.writer().print("  call @{s}({s}, {})\n", .{ setter, ctx_var, @as(i64, if (bool_value) 1 else 0) });
                            continue;
                        }
                    }
                    var expr_arena = std.heap.ArenaAllocator.init(self.allocator);
                    defer expr_arena.deinit();
                    const prefix = try std.fmt.allocPrint(self.allocator, "prop_expr_{s}_{d}", .{ node.alias, idx });
                    defer self.allocator.free(prefix);
                    const value = try self.emitInterpolationExpr(out, expr, prefix, expr_arena.allocator());
                    const setter = try self.componentStateSetterName(node.tag, target_prop.name);
                    defer self.allocator.free(setter);
                    switch (target_state.ty) {
                        .i64 => {
                            if (value.ty != .i64) return LowerError.InvalidInterpolation;
                            try out.writer().print("  call @{s}({s}, {s})\n", .{ setter, ctx_var, value.name });
                        },
                        .i32 => {
                            if (value.ty != .i64) return LowerError.InvalidInterpolation;
                            try out.writer().print("  call @{s}({s}, {s})\n", .{ setter, ctx_var, value.name });
                        },
                        .i1 => {
                            switch (value.ty) {
                                .i64 => try out.writer().print("  call @{s}({s}, {s})\n", .{ setter, ctx_var, value.name }),
                                .i1 => {
                                    const wide_name = try std.fmt.allocPrint(self.allocator, "prop_i1_wide_{s}_{d}", .{ node.alias, idx });
                                    defer self.allocator.free(wide_name);
                                    try out.writer().print("  {s} = zext {s} as i64\n", .{ wide_name, value.name });
                                    try out.writer().print("  call @{s}({s}, {s})\n", .{ setter, ctx_var, wide_name });
                                },
                                else => return LowerError.InvalidInterpolation,
                            }
                        },
                        .f64 => {
                            if (value.ty != .f64 and value.ty != .i64) return LowerError.InvalidInterpolation;
                            try out.writer().print("  call @{s}({s}, {s})\n", .{ setter, ctx_var, value.name });
                        },
                        .ptr => unreachable,
                    }
                },
                .template => |pieces| {
                    if (target_state.ty != .ptr) continue;
                    const setter = try self.componentStringStateSetterName(node.tag, target_prop.name);
                    defer self.allocator.free(setter);
                    const prefix = try std.fmt.allocPrint(self.allocator, "prop_tpl_{s}_{d}", .{ node.alias, idx });
                    defer self.allocator.free(prefix);
                    const slice = if (attr.is_object_prop)
                        try self.emitJsonTemplateBuffer(out, pieces, prefix)
                    else
                        try self.emitTemplateBuffer(out, pieces, prefix);
                    defer self.allocator.free(slice.ptr_name);
                    defer self.allocator.free(slice.len_name);
                    if (attr.is_object_prop) {
                        const normalized = try self.emitJsonNormalizeObjectBuffer(out, slice, prefix, self.jsonTemplateBufferSize(pieces));
                        defer self.allocator.free(normalized.ptr_name);
                        defer self.allocator.free(normalized.len_name);
                        try out.writer().print("  call @{s}({s}, *{s}, {s})\n", .{ setter, ctx_var, normalized.ptr_name, normalized.len_name });
                    } else {
                        try out.writer().print("  call @{s}({s}, *{s}, {s})\n", .{ setter, ctx_var, slice.ptr_name, slice.len_name });
                    }
                },
            }
        }
    }

    fn emitInheritedContextProp(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        provider_node: parser.DomNode,
        child_node: parser.DomNode,
        provider_ctx_var: []const u8,
        child_ctx_var: []const u8,
        prop_name: []const u8,
        prefix: []const u8,
    ) !void {
        const source_prop = self.componentStateProp(provider_node.tag, prop_name) orelse return;
        const target_prop = self.componentStateProp(child_node.tag, prop_name) orelse return;
        if (self.childHasExplicitComponentProp(child_node, target_prop.name)) return;
        if (source_prop.state.ty != target_prop.state.ty) return;

        const provider_state = try std.fmt.allocPrint(self.allocator, "{s}_state", .{prefix});
        defer self.allocator.free(provider_state);
        try out.writer().print("  {s} = load {s}+0 as ptr\n", .{ provider_state, provider_ctx_var });

        const source_slot = self.componentStateSlotOffset(provider_node.tag, source_prop.name) orelse return;

        switch (source_prop.state.ty) {
            .ptr => {
                const len_name = try self.stateLenVarName(source_prop.name);
                defer self.allocator.free(len_name);
                const len_state = self.componentStateVar(provider_node.tag, len_name) orelse return;
                if (len_state.ty != .i64) return;
                const len_slot = self.componentStateSlotOffset(provider_node.tag, len_name) orelse return;
                const ptr_value = try std.fmt.allocPrint(self.allocator, "{s}_ptr", .{prefix});
                defer self.allocator.free(ptr_value);
                const len_value = try std.fmt.allocPrint(self.allocator, "{s}_len", .{prefix});
                defer self.allocator.free(len_value);
                const setter = try self.componentStringStateSetterName(child_node.tag, target_prop.name);
                defer self.allocator.free(setter);
                try out.writer().print("  {s} = load {s}+{} as ptr\n", .{ ptr_value, provider_state, source_slot });
                try out.writer().print("  {s} = load {s}+{} as i64\n", .{ len_value, provider_state, len_slot });
                try out.writer().print("  call @{s}({s}, *{s}, {s})\n", .{ setter, child_ctx_var, ptr_value, len_value });
            },
            .i1 => {
                const raw_value = try std.fmt.allocPrint(self.allocator, "{s}_raw", .{prefix});
                defer self.allocator.free(raw_value);
                const wide_value = try std.fmt.allocPrint(self.allocator, "{s}_wide", .{prefix});
                defer self.allocator.free(wide_value);
                const setter = try self.componentStateSetterName(child_node.tag, target_prop.name);
                defer self.allocator.free(setter);
                try out.writer().print("  {s} = load {s}+{} as i1\n", .{ raw_value, provider_state, source_slot });
                try out.writer().print("  {s} = zext {s} as i64\n", .{ wide_value, raw_value });
                try out.writer().print("  call @{s}({s}, {s})\n", .{ setter, child_ctx_var, wide_value });
            },
            .i32 => {
                const raw_value = try std.fmt.allocPrint(self.allocator, "{s}_raw", .{prefix});
                defer self.allocator.free(raw_value);
                const wide_value = try std.fmt.allocPrint(self.allocator, "{s}_wide", .{prefix});
                defer self.allocator.free(wide_value);
                const setter = try self.componentStateSetterName(child_node.tag, target_prop.name);
                defer self.allocator.free(setter);
                try out.writer().print("  {s} = load {s}+{} as i32\n", .{ raw_value, provider_state, source_slot });
                try out.writer().print("  {s} = sext {s} as i64\n", .{ wide_value, raw_value });
                try out.writer().print("  call @{s}({s}, {s})\n", .{ setter, child_ctx_var, wide_value });
            },
            .i64, .f64 => {
                const value = try std.fmt.allocPrint(self.allocator, "{s}_value", .{prefix});
                defer self.allocator.free(value);
                const setter = try self.componentStateSetterName(child_node.tag, target_prop.name);
                defer self.allocator.free(setter);
                try out.writer().print("  {s} = load {s}+{} as i64\n", .{ value, provider_state, source_slot });
                try out.writer().print("  call @{s}({s}, {s})\n", .{ setter, child_ctx_var, value });
            },
        }
    }

    fn emitInheritedContextProps(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        provider_node: parser.DomNode,
        child_node: parser.DomNode,
        provider_ctx_var: []const u8,
        child_ctx_var: []const u8,
        prefix_base: []const u8,
    ) !void {
        const provider_component = self.componentByName(provider_node.tag) orelse return;
        const props = self.componentEffectiveSlotContextProps(provider_component) orelse return;
        var start: usize = 0;
        var ordinal: usize = 0;
        while (start < props.len) {
            while (start < props.len and isContextPropListDelimiter(props[start])) start += 1;
            if (start >= props.len) break;
            var end = start;
            while (end < props.len and !isContextPropListDelimiter(props[end])) end += 1;
            const prop_name = props[start..end];
            const prefix = try std.fmt.allocPrint(self.allocator, "{s}_ctx_{d}", .{ prefix_base, ordinal });
            defer self.allocator.free(prefix);
            try self.emitInheritedContextProp(out, provider_node, child_node, provider_ctx_var, child_ctx_var, prop_name, prefix);
            ordinal += 1;
            start = end;
        }
    }

    fn emitUserComponentEventBinding(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        root_var: []const u8,
        attr: parser.Attribute,
        event_name: []const u8,
        handler_name: []const u8,
        owner_ctx_var: []const u8,
    ) !void {
        const evt_idx = try self.string_pool.add(event_name);
        const evt_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, evt_idx });
        defer self.allocator.free(evt_const);
        const handler_export = try self.handlerExportName(handler_name);
        defer self.allocator.free(handler_export);
        const handler_idx = try self.string_pool.add(handler_export);
        const handler_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, handler_idx });
        defer self.allocator.free(handler_const);
        const bind_fn = if (isCaptureEventAttr(attr.name)) "sax_dom_bind_event_capture" else "sax_dom_bind_event";
        try out.writer().print("  call @{s}({s}, *{s}, {}, *{s}, {}, {s})\n", .{ bind_fn, root_var, evt_const, event_name.len, handler_const, handler_export.len, owner_ctx_var });
    }

    fn emitUserComponentEventBindings(self: *SaxLowerer, out: *std.ArrayList(u8), node: parser.DomNode, ctx_var: []const u8, owner_ctx_var: []const u8) !void {
        var has_event = false;
        for (node.attrs) |attr| {
            if (attr.is_event) {
                has_event = true;
                break;
            }
        }
        if (!has_event) return;

        const stem = try self.componentExportStem(node.tag);
        defer self.allocator.free(stem);
        const root_var = try std.fmt.allocPrint(self.allocator, "{s}_root", .{ctx_var});
        defer self.allocator.free(root_var);
        try out.writer().print("  {s} = call @sax_{s}_root({s})\n", .{ root_var, stem, ctx_var });

        for (node.attrs) |attr| {
            if (!attr.is_event) continue;
            const handler_name = attr.event_handler orelse return LowerError.UnknownHandler;
            if (self.event_handlers.get(handler_name) == null) return LowerError.UnknownHandler;

            const base_attr = eventBaseAttrName(attr.name);
            if (std.mem.eql(u8, base_attr, "onchange")) {
                if (self.componentPreferredOnChangeEvent(node.tag)) |event_name| {
                    try self.emitUserComponentEventBinding(out, root_var, attr, event_name, handler_name, owner_ctx_var);
                } else {
                    try self.emitUserComponentEventBinding(out, root_var, attr, "input", handler_name, owner_ctx_var);
                    try self.emitUserComponentEventBinding(out, root_var, attr, "change", handler_name, owner_ctx_var);
                }
                continue;
            }

            const event_name = domEventName(node, attr.name);
            try self.emitUserComponentEventBinding(out, root_var, attr, event_name, handler_name, owner_ctx_var);
        }
    }

    fn emitUserComponentMount(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        idx: usize,
        parent_var: []const u8,
        owner_ctx_var: []const u8,
        context_provider_node: ?parser.DomNode,
        context_provider_ctx_var: ?[]const u8,
        context_provider_descendants: bool,
    ) !void {
        const node = self.component.dom_nodes[idx];
        const stem = try self.componentExportStem(node.tag);
        defer self.allocator.free(stem);
        const ctx_var = try std.fmt.allocPrint(self.allocator, "node_{d}", .{idx});
        defer self.allocator.free(ctx_var);
        const node_slot = try self.nodeSlotConstName(node.alias);
        defer self.allocator.free(node_slot);
        try out.writer().print("  {s} = call @sax_{s}_mount({s})\n", .{ ctx_var, stem, parent_var });
        try out.writer().print("  store dom+{s}, {s} as ptr\n", .{ node_slot, ctx_var });
        try self.emitUserComponentRef(out, node, ctx_var, owner_ctx_var);
        if (context_provider_node) |provider_node| {
            try self.emitInheritedContextProps(out, provider_node, node, context_provider_ctx_var.?, ctx_var, node.alias);
        }
        try self.emitUserComponentProps(out, node, ctx_var);
        try self.emitUserComponentEventBindings(out, node, ctx_var, owner_ctx_var);
        if (node.children.len == 0) {
            try out.writer().print("  !{s}\n", .{ctx_var});
            return;
        }
        const slot_var = try std.fmt.allocPrint(self.allocator, "slot_{d}", .{idx});
        defer self.allocator.free(slot_var);
        try out.writer().print("  {s} = call @sax_{s}_slot({s})\n", .{ slot_var, stem, ctx_var });
        var text_idx: usize = 0;
        const current_provides_context = self.nodeProvidesContextProps(node);
        const current_provides_descendant_context = self.nodeProvidesDescendantContextProps(node);
        for (node.children, 0..) |child, child_order| {
            switch (child) {
                .node_index => |child_idx| {
                    const child_node = self.component.dom_nodes[child_idx];
                    if (child_node.is_user_component) {
                        const next_context_node: ?parser.DomNode = if (current_provides_context) node else if (context_provider_descendants) context_provider_node else null;
                        const next_context_ctx: ?[]const u8 = if (current_provides_context) ctx_var else if (context_provider_descendants) context_provider_ctx_var else null;
                        const next_context_descendants = if (current_provides_context) current_provides_descendant_context else context_provider_descendants;
                        try self.emitUserComponentMount(out, child_idx, slot_var, owner_ctx_var, next_context_node, next_context_ctx, next_context_descendants);
                    } else {
                        const child_var = try std.fmt.allocPrint(self.allocator, "node_{d}", .{child_idx});
                        defer self.allocator.free(child_var);
                        try out.writer().print("  call @sax_dom_append_child({s}, {s})\n", .{ slot_var, child_var });
                    }
                },
                .text => |piece| {
                    const projected_text_idx: ?usize = if (projectedTextPieceNeedsSlot(piece)) blk: {
                        const current = text_idx;
                        text_idx += 1;
                        break :blk current;
                    } else null;
                    try self.emitProjectedTextChild(out, piece, slot_var, node.alias, idx, child_order, projected_text_idx);
                },
            }
        }
        try out.writer().print("  !{s}\n", .{ctx_var});
    }

    fn emitProjectedTextChild(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        piece: parser.TextPiece,
        slot_var: []const u8,
        node_alias: []const u8,
        node_idx: usize,
        child_order: usize,
        projected_text_idx: ?usize,
    ) !void {
        const text_var = try std.fmt.allocPrint(self.allocator, "text_child_{d}_{d}", .{ node_idx, child_order });
        defer self.allocator.free(text_var);
        switch (piece) {
            .text => |txt| {
                if (txt.len == 0) return;
                const text_idx = try self.string_pool.add(txt);
                const text_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, text_idx });
                defer self.allocator.free(text_const);
                try out.writer().print("  {s} = call @sax_dom_create_text(*{s}, {})\n", .{ text_var, text_const, txt.len });
            },
            .interpolation => |expr| {
                if (simpleStateExprName(expr)) |name| {
                    if (self.stateVar(name)) |sv| {
                        if (sv.ty == .ptr) {
                            const prefix = try std.fmt.allocPrint(self.allocator, "text_child_{d}_{d}", .{ node_idx, child_order });
                            defer self.allocator.free(prefix);
                            const slice = try self.emitLoadStateStringSlice(out, name, prefix);
                            defer self.allocator.free(slice.ptr_name);
                            defer self.allocator.free(slice.len_name);
                            try out.writer().print("  {s} = call @sax_dom_create_text(*{s}, {s})\n", .{ text_var, slice.ptr_name, slice.len_name });
                            try out.writer().print("  call @sax_dom_append_child({s}, {s})\n", .{ slot_var, text_var });
                            try self.emitProjectedTextChildStore(out, node_alias, projected_text_idx, text_var);
                            return;
                        }
                    }
                }
                var expr_arena = std.heap.ArenaAllocator.init(self.allocator);
                defer expr_arena.deinit();
                const expr_prefix = try std.fmt.allocPrint(self.allocator, "text_child_expr_{d}_{d}", .{ node_idx, child_order });
                defer self.allocator.free(expr_prefix);
                const value = try self.emitInterpolationExpr(out, expr, expr_prefix, expr_arena.allocator());
                const tmp_buf_name = try std.fmt.allocPrint(self.allocator, "text_child_buf_{d}_{d}", .{ node_idx, child_order });
                defer self.allocator.free(tmp_buf_name);
                const tmp_len_name = try std.fmt.allocPrint(self.allocator, "text_child_len_{d}_{d}", .{ node_idx, child_order });
                defer self.allocator.free(tmp_len_name);
                try out.writer().print("  {s} = stack_alloc 64\n", .{tmp_buf_name});
                try self.emitFormatInterpolationValue(out, value, tmp_buf_name, tmp_len_name);
                try out.writer().print("  {s} = call @sax_dom_create_text(*{s}, {s})\n", .{ text_var, tmp_buf_name, tmp_len_name });
            },
            .json_string_interpolation => return LowerError.InvalidTextExpression,
            .json_object_spread => return LowerError.InvalidTextExpression,
        }
        try out.writer().print("  call @sax_dom_append_child({s}, {s})\n", .{ slot_var, text_var });
        try self.emitProjectedTextChildStore(out, node_alias, projected_text_idx, text_var);
    }

    fn emitProjectedTextChildStore(self: *SaxLowerer, out: *std.ArrayList(u8), node_alias: []const u8, projected_text_idx: ?usize, text_var: []const u8) !void {
        const text_idx = projected_text_idx orelse return;
        const text_slot_name = try self.textNodeSlotConstName(node_alias, text_idx);
        defer self.allocator.free(text_slot_name);
        try out.writer().print("  store dom+{s}, {s} as i64\n", .{ text_slot_name, text_var });
    }

    fn emitUserComponentContextPropUpdatesForChildren(self: *SaxLowerer, out: *std.ArrayList(u8), node: parser.DomNode, node_idx: usize, provider_ctx_var: []const u8) !void {
        const provider_component = self.componentByName(node.tag) orelse return;
        if (self.componentEffectiveSlotContextProps(provider_component) == null) return;
        for (node.children) |child| {
            const child_idx = switch (child) {
                .node_index => |child_idx| child_idx,
                .text => continue,
            };
            const child_node = self.component.dom_nodes[child_idx];
            if (!child_node.is_user_component) continue;
            const child_slot = try self.nodeSlotConstName(child_node.alias);
            defer self.allocator.free(child_slot);
            const child_ctx_var = try std.fmt.allocPrint(self.allocator, "context_child_{d}_{d}", .{ node_idx, child_idx });
            defer self.allocator.free(child_ctx_var);
            const prefix = try std.fmt.allocPrint(self.allocator, "render_{s}_{s}", .{ node.alias, child_node.alias });
            defer self.allocator.free(prefix);
            try out.writer().print("  {s} = load dom+{s} as ptr\n", .{ child_ctx_var, child_slot });
            try self.emitInheritedContextProps(out, node, child_node, provider_ctx_var, child_ctx_var, prefix);
            try out.writer().print("  !{s}\n", .{child_ctx_var});
        }
    }

    fn emitNodeAttachChildren(self: *SaxLowerer, out: *std.ArrayList(u8), idx: usize) !void {
        const node = self.component.dom_nodes[idx];
        if (node.is_user_component) return;
        if (node.self_closing) return;

        const node_var = try std.fmt.allocPrint(self.allocator, "node_{d}", .{idx});
        defer self.allocator.free(node_var);

        var text_idx: usize = 0;
        for (node.children) |child| {
            switch (child) {
                .node_index => |child_idx| {
                    const child_node = self.component.dom_nodes[child_idx];
                    if (child_node.is_user_component) {
                        try self.emitUserComponentMount(out, child_idx, node_var, "ctx", null, null, false);
                    } else {
                        const child_var = try std.fmt.allocPrint(self.allocator, "node_{d}", .{child_idx});
                        defer self.allocator.free(child_var);
                        try out.writer().print("  call @sax_dom_append_child({s}, {s})\n", .{ node_var, child_var });
                    }
                },
                .text => |piece| {
                    if (!textPieceNeedsSeparateNode(piece)) continue;
                    const slot = self.node_slots[idx];
                    if (slot.text_slot_count == 0) continue;
                    const text_slot_name = try self.textNodeSlotConstName(node.alias, text_idx);
                    defer self.allocator.free(text_slot_name);
                    const text_var = try std.fmt.allocPrint(self.allocator, "text_node_{d}_{d}", .{ idx, text_idx });
                    defer self.allocator.free(text_var);
                    try out.writer().print("  {s} = load dom+{s} as i64\n", .{ text_var, text_slot_name });
                    try out.writer().print("  call @sax_dom_append_child({s}, {s})\n", .{ node_var, text_var });
                    text_idx += 1;
                },
            }
        }
    }

    fn emitDeferredInitialFormValuesAfterAttach(self: *SaxLowerer, out: *std.ArrayList(u8)) !void {
        for (self.component.dom_nodes, 0..) |node, idx| {
            if (node.is_user_component) continue;
            const node_var = try std.fmt.allocPrint(self.allocator, "node_{d}", .{idx});
            defer self.allocator.free(node_var);
            try self.emitDeferredSelectDefaultValue(out, node, node_var);
        }
    }

    fn emitDeferredSelectDefaultValue(self: *SaxLowerer, out: *std.ArrayList(u8), node: parser.DomNode, node_var: []const u8) !void {
        if (!std.mem.eql(u8, node.tag, "select")) return;
        for (node.attrs) |attr| {
            if (!std.mem.eql(u8, attr.name, "defaultValue")) continue;
            switch (attr.value) {
                .literal => |lit| {
                    const val_idx = try self.string_pool.add(lit);
                    const val_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, val_idx });
                    defer self.allocator.free(val_const);
                    try out.writer().print("  call @sax_dom_set_value({s}, *{s}, {})\n", .{ node_var, val_const, lit.len });
                },
                .interpolation => |expr| try self.emitInterpolatedValue(out, node_var, attr.name, expr, true, true),
                .template => |pieces| {
                    const prefix = try std.fmt.allocPrint(self.allocator, "attr_tpl_{s}_{s}", .{ node_var, attr.name });
                    defer self.allocator.free(prefix);
                    const slice = try self.emitTemplateBuffer(out, pieces, prefix);
                    defer self.allocator.free(slice.ptr_name);
                    defer self.allocator.free(slice.len_name);
                    try out.writer().print("  call @sax_dom_set_value({s}, *{s}, {s})\n", .{ node_var, slice.ptr_name, slice.len_name });
                },
            }
            return;
        }
    }

    fn emitAutofocusAfterMount(self: *SaxLowerer, out: *std.ArrayList(u8)) !void {
        for (self.component.dom_nodes, 0..) |node, idx| {
            if (node.is_user_component) continue;
            for (node.attrs) |attr| {
                if (!nodeUsesAutofocusProperty(attr.name)) continue;
                const node_var = try std.fmt.allocPrint(self.allocator, "node_{d}", .{idx});
                defer self.allocator.free(node_var);
                switch (attr.value) {
                    .literal => |lit| {
                        if (literalBoolValue(lit) orelse true) {
                            try out.writer().print("  call @sax_dom_focus({s})\n", .{node_var});
                        }
                    },
                    .interpolation => |expr| {
                        var expr_arena = std.heap.ArenaAllocator.init(self.allocator);
                        defer expr_arena.deinit();
                        const expr_prefix = try std.fmt.allocPrint(self.allocator, "autofocus_expr_{s}", .{node_var});
                        defer self.allocator.free(expr_prefix);
                        const value = try self.emitInterpolationExpr(out, expr, expr_prefix, expr_arena.allocator());
                        if (value.ty != .i64) return LowerError.InvalidInterpolation;
                        const bool_name = try std.fmt.allocPrint(self.allocator, "autofocus_{s}", .{node_var});
                        defer self.allocator.free(bool_name);
                        const label_prefix = try self.allocLabelPrefix(node_var);
                        defer self.allocator.free(label_prefix);
                        const focus_label = try std.fmt.allocPrint(self.allocator, "L_AUTOFOCUS_{s}", .{label_prefix});
                        defer self.allocator.free(focus_label);
                        const done_label = try std.fmt.allocPrint(self.allocator, "L_AUTOFOCUS_DONE_{s}", .{label_prefix});
                        defer self.allocator.free(done_label);
                        try out.writer().print("  {s} = ne {s}, 0\n", .{ bool_name, value.name });
                        try out.writer().print("  br {s} -> {s}, {s}\n", .{ bool_name, focus_label, done_label });
                        try out.writer().print("{s}:\n", .{focus_label});
                        try out.writer().print("  call @sax_dom_focus({s})\n", .{node_var});
                        try out.writer().print("  jmp {s}\n", .{done_label});
                        try out.writer().print("{s}:\n", .{done_label});
                    },
                    .template => {},
                }
                break;
            }
        }
    }

    fn nodeSlotConstName(self: *const SaxLowerer, alias: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_node_{s}", .{ self.component.name, alias });
    }

    fn textNodeSlotConstName(self: *const SaxLowerer, alias: []const u8, text_idx: usize) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_node_{s}_text_{d}", .{ self.component.name, alias, text_idx });
    }

    fn nodeKeyConstName(self: *const SaxLowerer, alias: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "sax_{s}_key_{s}", .{ self.component.name, alias });
    }

    fn emitTextPieceWrite(
        self: *SaxLowerer,
        out: *std.ArrayList(u8),
        piece: parser.TextPiece,
        text_var: []const u8,
        prefix: []const u8,
        create: bool,
    ) !bool {
        switch (piece) {
            .text => |txt| {
                if (txt.len == 0) return false;
                const text_idx = try self.string_pool.add(txt);
                const text_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, text_idx });
                defer self.allocator.free(text_const);
                if (create) {
                    try out.writer().print("  {s} = call @sax_dom_create_text(*{s}, {})\n", .{ text_var, text_const, txt.len });
                } else {
                    try out.writer().print("  call @sax_dom_set_text({s}, *{s}, {})\n", .{ text_var, text_const, txt.len });
                }
                return true;
            },
            .interpolation => |expr| {
                if (simpleStateExprName(expr)) |name| {
                    if (self.stateVar(name)) |sv| {
                        if (sv.ty == .ptr) {
                            const slice = try self.emitLoadStateStringSlice(out, name, prefix);
                            defer self.allocator.free(slice.ptr_name);
                            defer self.allocator.free(slice.len_name);
                            if (create) {
                                try out.writer().print("  {s} = call @sax_dom_create_text(*{s}, {s})\n", .{ text_var, slice.ptr_name, slice.len_name });
                            } else {
                                try out.writer().print("  call @sax_dom_set_text({s}, *{s}, {s})\n", .{ text_var, slice.ptr_name, slice.len_name });
                            }
                            return true;
                        }
                    }
                }

                var expr_arena = std.heap.ArenaAllocator.init(self.allocator);
                defer expr_arena.deinit();
                const value = try self.emitInterpolationExpr(out, expr, prefix, expr_arena.allocator());
                const tmp_buf_name = try std.fmt.allocPrint(self.allocator, "{s}_buf", .{prefix});
                defer self.allocator.free(tmp_buf_name);
                const tmp_len_name = try std.fmt.allocPrint(self.allocator, "{s}_len", .{prefix});
                defer self.allocator.free(tmp_len_name);
                try out.writer().print("  {s} = stack_alloc 64\n", .{tmp_buf_name});
                try self.emitFormatInterpolationValue(out, value, tmp_buf_name, tmp_len_name);
                if (create) {
                    try out.writer().print("  {s} = call @sax_dom_create_text(*{s}, {s})\n", .{ text_var, tmp_buf_name, tmp_len_name });
                } else {
                    try out.writer().print("  call @sax_dom_set_text({s}, *{s}, {s})\n", .{ text_var, tmp_buf_name, tmp_len_name });
                }
                return true;
            },
            .json_string_interpolation => return LowerError.InvalidTextExpression,
            .json_object_spread => return LowerError.InvalidTextExpression,
        }
    }

    fn emitNodeRender(self: *SaxLowerer, out: *std.ArrayList(u8), ctx_var: []const u8, idx: usize) !void {
        const node = self.component.dom_nodes[idx];
        const node_var = try std.fmt.allocPrint(self.allocator, "node_{d}", .{idx});
        defer self.allocator.free(node_var);

        const node_slot = try self.nodeSlotConstName(node.alias);
        defer self.allocator.free(node_slot);
        if (node.is_user_component) {
            const stem = try self.componentExportStem(node.tag);
            defer self.allocator.free(stem);
            try out.writer().print("  {s} = load dom+{s} as ptr\n", .{ node_var, node_slot });
            try self.emitUserComponentProps(out, node, node_var);
            try out.writer().print("  call @sax_{s}_render({s})\n", .{ stem, node_var });
            try self.emitUserComponentContextPropUpdatesForChildren(out, node, idx, node_var);
            try self.emitProjectedTextChildRender(out, node, idx);
            try out.writer().print("  !{s}\n", .{node_var});
            return;
        }
        try out.writer().print("  {s} = load dom+{s} as ptr\n", .{ node_var, node_slot });
        try self.emitNodeAttrs(out, node, node_var, ctx_var, false, false);
        if (self.node_slots[idx].text_slot_count != 0) {
            try self.emitSeparateTextNodeRender(out, node, idx);
        } else {
            try self.emitTextPieceBuffer(out, node, node_var);
        }
        try out.writer().print("  !{s}\n", .{node_var});
    }

    fn emitSeparateTextNodeRender(self: *SaxLowerer, out: *std.ArrayList(u8), node: parser.DomNode, idx: usize) !void {
        var text_idx: usize = 0;
        var child_order: usize = 0;
        for (node.children) |child| {
            defer child_order += 1;
            const piece = switch (child) {
                .text => |piece| piece,
                .node_index => continue,
            };
            if (!textPieceNeedsSeparateNode(piece)) continue;
            const text_slot_name = try self.textNodeSlotConstName(node.alias, text_idx);
            defer self.allocator.free(text_slot_name);
            const text_var = try std.fmt.allocPrint(self.allocator, "text_node_render_{d}_{d}", .{ idx, text_idx });
            defer self.allocator.free(text_var);
            try out.writer().print("  {s} = load dom+{s} as i64\n", .{ text_var, text_slot_name });
            const prefix = try std.fmt.allocPrint(self.allocator, "text_node_render_{s}_{d}_{d}", .{ node.alias, text_idx, child_order });
            defer self.allocator.free(prefix);
            _ = try self.emitTextPieceWrite(out, piece, text_var, prefix, false);
            text_idx += 1;
        }
    }

    fn emitProjectedTextChildRender(self: *SaxLowerer, out: *std.ArrayList(u8), node: parser.DomNode, idx: usize) !void {
        if (self.node_slots[idx].text_slot_count == 0) return;
        var text_idx: usize = 0;
        var child_order: usize = 0;
        for (node.children) |child| {
            defer child_order += 1;
            const piece = switch (child) {
                .text => |piece| piece,
                .node_index => continue,
            };
            if (!projectedTextPieceNeedsSlot(piece)) continue;
            if (projectedTextPieceNeedsRender(piece)) {
                const text_slot_name = try self.textNodeSlotConstName(node.alias, text_idx);
                defer self.allocator.free(text_slot_name);
                const text_var = try std.fmt.allocPrint(self.allocator, "projected_text_render_{d}_{d}", .{ idx, text_idx });
                defer self.allocator.free(text_var);
                try out.writer().print("  {s} = load dom+{s} as i64\n", .{ text_var, text_slot_name });
                const prefix = try std.fmt.allocPrint(self.allocator, "projected_text_render_{s}_{d}_{d}", .{ node.alias, text_idx, child_order });
                defer self.allocator.free(prefix);
                _ = try self.emitTextPieceWrite(out, piece, text_var, prefix, false);
            }
            text_idx += 1;
        }
    }

    fn emitInterpolatedBoolProperty(self: *SaxLowerer, out: *std.ArrayList(u8), node_var: []const u8, key_name: []const u8, property_name: []const u8, setter_name: []const u8, expr: parser.Expr) !void {
        var expr_arena = std.heap.ArenaAllocator.init(self.allocator);
        defer expr_arena.deinit();
        const expr_prefix = try std.fmt.allocPrint(self.allocator, "{s}_expr_{s}_{s}", .{ property_name, node_var, key_name });
        defer self.allocator.free(expr_prefix);
        const value = try self.emitInterpolationExpr(out, expr, expr_prefix, expr_arena.allocator());
        if (value.ty != .i64) return LowerError.InvalidInterpolation;
        const bool_name = try std.fmt.allocPrint(self.allocator, "{s}_{s}_{s}", .{ property_name, node_var, key_name });
        defer self.allocator.free(bool_name);
        try out.writer().print("  {s} = ne {s}, 0\n", .{ bool_name, value.name });
        try out.writer().print("  call @{s}({s}, {s})\n", .{ setter_name, node_var, bool_name });
    }

    fn emitLiteralGenericBoolProperty(self: *SaxLowerer, out: *std.ArrayList(u8), node_var: []const u8, prop_name: []const u8, value: bool) !void {
        const prop_idx = try self.string_pool.add(prop_name);
        const prop_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, prop_idx });
        defer self.allocator.free(prop_const);
        try out.writer().print("  call @sax_dom_set_bool_prop({s}, *{s}, {}, {s})\n", .{ node_var, prop_const, prop_name.len, if (value) "1" else "0" });
    }

    fn emitInterpolatedGenericBoolProperty(self: *SaxLowerer, out: *std.ArrayList(u8), node_var: []const u8, attr_name: []const u8, prop_name: []const u8, expr: parser.Expr) !void {
        var expr_arena = std.heap.ArenaAllocator.init(self.allocator);
        defer expr_arena.deinit();
        const expr_prefix = try std.fmt.allocPrint(self.allocator, "boolprop_{s}_{s}", .{ node_var, attr_name });
        defer self.allocator.free(expr_prefix);
        const value = try self.emitInterpolationExpr(out, expr, expr_prefix, expr_arena.allocator());
        if (value.ty != .i64) return LowerError.InvalidInterpolation;
        const bool_name = try std.fmt.allocPrint(self.allocator, "boolprop_{s}_{s}", .{ node_var, attr_name });
        defer self.allocator.free(bool_name);
        const prop_idx = try self.string_pool.add(prop_name);
        const prop_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, prop_idx });
        defer self.allocator.free(prop_const);
        try out.writer().print("  {s} = ne {s}, 0\n", .{ bool_name, value.name });
        try out.writer().print("  call @sax_dom_set_bool_prop({s}, *{s}, {}, {s})\n", .{ node_var, prop_const, prop_name.len, bool_name });
    }

    fn emitLiteralGenericStringProperty(self: *SaxLowerer, out: *std.ArrayList(u8), node_var: []const u8, prop_name: []const u8, value: []const u8) !void {
        const prop_idx = try self.string_pool.add(prop_name);
        const prop_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, prop_idx });
        defer self.allocator.free(prop_const);
        const val_idx = try self.string_pool.add(value);
        const val_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, val_idx });
        defer self.allocator.free(val_const);
        try out.writer().print("  call @sax_dom_set_str_prop({s}, *{s}, {}, *{s}, {})\n", .{ node_var, prop_const, prop_name.len, val_const, value.len });
    }

    fn emitGenericStringPropertySlice(self: *SaxLowerer, out: *std.ArrayList(u8), node_var: []const u8, prop_name: []const u8, ptr_name: []const u8, len_name: []const u8) !void {
        const prop_idx = try self.string_pool.add(prop_name);
        const prop_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, prop_idx });
        defer self.allocator.free(prop_const);
        try out.writer().print("  call @sax_dom_set_str_prop({s}, *{s}, {}, *{s}, {s})\n", .{ node_var, prop_const, prop_name.len, ptr_name, len_name });
    }

    fn emitLiteralTranslateProperty(self: *SaxLowerer, out: *std.ArrayList(u8), node_var: []const u8, value: []const u8) !void {
        const val_idx = try self.string_pool.add(value);
        const val_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, val_idx });
        defer self.allocator.free(val_const);
        try out.writer().print("  call @sax_dom_set_translate({s}, *{s}, {})\n", .{ node_var, val_const, value.len });
    }

    fn emitTranslatePropertySlice(_: *SaxLowerer, out: *std.ArrayList(u8), node_var: []const u8, ptr_name: []const u8, len_name: []const u8) !void {
        try out.writer().print("  call @sax_dom_set_translate({s}, *{s}, {s})\n", .{ node_var, ptr_name, len_name });
    }

    fn emitInterpolatedTranslateProperty(self: *SaxLowerer, out: *std.ArrayList(u8), node_var: []const u8, attr_name: []const u8, expr: parser.Expr) !void {
        if (simpleStateExprName(expr)) |state_name| {
            if (self.stateVar(state_name)) |sv| {
                if (sv.ty == .ptr) {
                    const prefix = try std.fmt.allocPrint(self.allocator, "translate_str_{s}_{s}", .{ node_var, attr_name });
                    defer self.allocator.free(prefix);
                    const slice = try self.emitLoadStateStringSlice(out, state_name, prefix);
                    defer self.allocator.free(slice.ptr_name);
                    defer self.allocator.free(slice.len_name);
                    try self.emitTranslatePropertySlice(out, node_var, slice.ptr_name, slice.len_name);
                    return;
                }
            }
        }

        var expr_arena = std.heap.ArenaAllocator.init(self.allocator);
        defer expr_arena.deinit();
        const expr_prefix = try std.fmt.allocPrint(self.allocator, "translate_expr_{s}_{s}", .{ node_var, attr_name });
        defer self.allocator.free(expr_prefix);
        const value = try self.emitInterpolationExpr(out, expr, expr_prefix, expr_arena.allocator());
        const tmp_buf_name = try std.fmt.allocPrint(self.allocator, "translate_tmp_{s}_{s}", .{ node_var, attr_name });
        defer self.allocator.free(tmp_buf_name);
        const tmp_len_name = try std.fmt.allocPrint(self.allocator, "translate_tmp_len_{s}_{s}", .{ node_var, attr_name });
        defer self.allocator.free(tmp_len_name);
        try out.writer().print("  {s} = stack_alloc 64\n", .{tmp_buf_name});
        try self.emitFormatInterpolationValue(out, value, tmp_buf_name, tmp_len_name);
        try self.emitTranslatePropertySlice(out, node_var, tmp_buf_name, tmp_len_name);
    }

    fn emitInterpolatedGenericStringProperty(self: *SaxLowerer, out: *std.ArrayList(u8), node_var: []const u8, attr_name: []const u8, prop_name: []const u8, expr: parser.Expr) !void {
        if (simpleStateExprName(expr)) |state_name| {
            if (self.stateVar(state_name)) |sv| {
                if (sv.ty == .ptr) {
                    const prefix = try std.fmt.allocPrint(self.allocator, "strprop_str_{s}_{s}", .{ node_var, attr_name });
                    defer self.allocator.free(prefix);
                    const slice = try self.emitLoadStateStringSlice(out, state_name, prefix);
                    defer self.allocator.free(slice.ptr_name);
                    defer self.allocator.free(slice.len_name);
                    try self.emitGenericStringPropertySlice(out, node_var, prop_name, slice.ptr_name, slice.len_name);
                    return;
                }
            }
        }
        if (self.parseStaticStringTernary(expr)) |ternary| {
            const ternary_prefix = try std.fmt.allocPrint(self.allocator, "strprop_{s}_{s}", .{ node_var, attr_name });
            defer self.allocator.free(ternary_prefix);
            const buf_name = try std.fmt.allocPrint(self.allocator, "strprop_buf_{s}_{s}", .{ node_var, attr_name });
            defer self.allocator.free(buf_name);
            const len_name = try std.fmt.allocPrint(self.allocator, "strprop_len_{s}_{s}", .{ node_var, attr_name });
            defer self.allocator.free(len_name);
            try out.writer().print("  {s} = stack_alloc {}\n", .{ buf_name, @max(@max(ternary.true_text.len, ternary.false_text.len), 1) });
            try out.writer().print("  {s} = 0\n", .{len_name});
            try self.emitStaticStringTernaryCopy(out, ternary, buf_name, len_name, ternary_prefix, 0);
            try self.emitGenericStringPropertySlice(out, node_var, prop_name, buf_name, len_name);
            return;
        }
        var expr_arena = std.heap.ArenaAllocator.init(self.allocator);
        defer expr_arena.deinit();
        const expr_prefix = try std.fmt.allocPrint(self.allocator, "strprop_{s}_{s}", .{ node_var, attr_name });
        defer self.allocator.free(expr_prefix);
        const value = try self.emitInterpolationExpr(out, expr, expr_prefix, expr_arena.allocator());
        const buf_name = try std.fmt.allocPrint(self.allocator, "strprop_buf_{s}_{s}", .{ node_var, attr_name });
        defer self.allocator.free(buf_name);
        const len_name = try std.fmt.allocPrint(self.allocator, "strprop_len_{s}_{s}", .{ node_var, attr_name });
        defer self.allocator.free(len_name);
        try out.writer().print("  {s} = stack_alloc 64\n", .{buf_name});
        try self.emitFormatInterpolationValue(out, value, buf_name, len_name);
        try self.emitGenericStringPropertySlice(out, node_var, prop_name, buf_name, len_name);
    }

    fn emitInterpolatedValue(self: *SaxLowerer, out: *std.ArrayList(u8), node_var: []const u8, key_name: []const u8, expr: parser.Expr, is_attr: bool, use_value_property: bool) !void {
        if (is_attr) {
            if (!use_value_property) {
                if (self.parseStaticStringTernary(expr)) |ternary| {
                    const key_idx = try self.string_pool.add(key_name);
                    const key_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, key_idx });
                    defer self.allocator.free(key_const);
                    const ternary_prefix = try std.fmt.allocPrint(self.allocator, "attr_ternary_{s}_{s}", .{ node_var, key_name });
                    defer self.allocator.free(ternary_prefix);
                    const buf_name = try std.fmt.allocPrint(self.allocator, "attr_ternary_buf_{s}_{s}", .{ node_var, key_name });
                    defer self.allocator.free(buf_name);
                    const len_name = try std.fmt.allocPrint(self.allocator, "attr_ternary_len_{s}_{s}", .{ node_var, key_name });
                    defer self.allocator.free(len_name);
                    try out.writer().print("  {s} = stack_alloc {}\n", .{ buf_name, @max(@max(ternary.true_text.len, ternary.false_text.len), 1) });
                    try out.writer().print("  {s} = 0\n", .{len_name});
                    try self.emitStaticStringTernaryCopy(out, ternary, buf_name, len_name, ternary_prefix, 0);
                    try out.writer().print("  call @sax_dom_set_attr({s}, *{s}, {}, *{s}, {s})\n", .{ node_var, key_const, key_name.len, buf_name, len_name });
                    return;
                }
            }
            if (simpleStateExprName(expr)) |state_name| {
                if (self.stateVar(state_name)) |sv| {
                    if (sv.ty == .ptr) {
                        const prefix = try std.fmt.allocPrint(self.allocator, "attr_str_{s}_{s}", .{ node_var, key_name });
                        defer self.allocator.free(prefix);
                        const slice = try self.emitLoadStateStringSlice(out, state_name, prefix);
                        defer self.allocator.free(slice.ptr_name);
                        defer self.allocator.free(slice.len_name);
                        if (use_value_property) {
                            try out.writer().print("  call @sax_dom_set_value({s}, *{s}, {s})\n", .{ node_var, slice.ptr_name, slice.len_name });
                            return;
                        }
                        const key_idx = try self.string_pool.add(key_name);
                        const key_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, key_idx });
                        defer self.allocator.free(key_const);
                        try out.writer().print("  call @sax_dom_set_attr({s}, *{s}, {}, *{s}, {s})\n", .{
                            node_var,
                            key_const,
                            key_name.len,
                            slice.ptr_name,
                            slice.len_name,
                        });
                        return;
                    }
                }
            }
        }

        var expr_arena = std.heap.ArenaAllocator.init(self.allocator);
        defer expr_arena.deinit();
        const expr_prefix = try std.fmt.allocPrint(self.allocator, "attr_expr_{s}_{s}", .{ node_var, key_name });
        defer self.allocator.free(expr_prefix);
        const value = try self.emitInterpolationExpr(out, expr, expr_prefix, expr_arena.allocator());

        const buf_name = try std.fmt.allocPrint(self.allocator, "interp_buf_{s}", .{key_name});
        defer self.allocator.free(buf_name);
        const len_name = try std.fmt.allocPrint(self.allocator, "interp_len_{s}", .{key_name});
        defer self.allocator.free(len_name);
        try out.writer().print("  {s} = stack_alloc 64\n", .{buf_name});
        try self.emitFormatInterpolationValue(out, value, buf_name, len_name);
        if (is_attr) {
            if (use_value_property) {
                try out.writer().print("  call @sax_dom_set_value({s}, *{s}, {s})\n", .{
                    node_var,
                    buf_name,
                    len_name,
                });
                return;
            }
            const key_idx = try self.string_pool.add(key_name);
            const key_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, key_idx });
            defer self.allocator.free(key_const);
            try out.writer().print("  call @sax_dom_set_attr({s}, *{s}, {}, *{s}, {s})\n", .{
                node_var,
                key_const,
                key_name.len,
                buf_name,
                len_name,
            });
        } else {
            try out.writer().print("  call @sax_dom_set_text({s}, *{s}, {s})\n", .{
                node_var,
                buf_name,
                len_name,
            });
        }
    }

    fn compileSlaHandlerBody(self: *SaxLowerer, handler: parser.Handler) ![]const u8 {
        var fields = try self.allocator.alloc(sla_handler_bridge.HandlerStateField, self.component.state_vars.len);
        defer self.allocator.free(fields);

        var addresses = std.ArrayList([]const u8).init(self.allocator);
        defer {
            for (addresses.items) |address| self.allocator.free(address);
            addresses.deinit();
        }

        for (self.component.state_vars, 0..) |sv, idx| {
            const slot_name = try self.stateSlotConstName(sv.name);
            defer self.allocator.free(slot_name);
            const address = try std.fmt.allocPrint(self.allocator, "state+{s}", .{slot_name});
            try addresses.append(address);
            fields[idx] = .{
                .name = sv.name,
                .ty = toSlaHandlerStateType(sv.ty),
                .address = address,
            };
        }

        return try sla_handler_bridge.compileHandler(self.allocator, handler.name, handler.body, fields, .{ .ambient_bindings = react_sla_ambient_bindings[0..] });
    }

    fn bodyUsesIdentifier(body: []const u8, name: []const u8) bool {
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, body, pos, name)) |idx| {
            const before_ok = idx == 0 or !(std.ascii.isAlphanumeric(body[idx - 1]) or body[idx - 1] == '_');
            const after_idx = idx + name.len;
            const after_ok = after_idx >= body.len or !(std.ascii.isAlphanumeric(body[after_idx]) or body[after_idx] == '_');
            if (before_ok and after_ok) return true;
            pos = after_idx;
        }
        return false;
    }

    fn emitSlaEventAmbientPrelude(self: *SaxLowerer, out: *std.ArrayList(u8), handler_name: []const u8, body: []const u8) !void {
        _ = self;
        const uses_current_value = bodyUsesIdentifier(body, "current_value") or bodyUsesIdentifier(body, "current_value_len");
        const uses_target_value_i64 = bodyUsesIdentifier(body, "target_value_i64");

        if (bodyUsesIdentifier(body, "checked")) {
            try out.writer().writeAll("  checked = call @sax_event_target_checked()\n");
        }
        if (bodyUsesIdentifier(body, "current_checked")) {
            try out.writer().writeAll("  current_checked = call @sax_event_current_target_checked()\n");
        }
        if (uses_current_value) {
            try out.writer().writeAll("  current_value = stack_alloc 1024\n");
            try out.writer().writeAll("  current_value_len = call @sax_event_target_value(*current_value, 1024)\n");
        }
        if (uses_target_value_i64) {
            _ = handler_name;
            try out.writer().writeAll("  target_value_i64 = call @sax_event_target_value_i64()\n");
        }
    }

    fn usesSlaEventValueI64(self: *const SaxLowerer) bool {
        for (self.component.handlers) |handler| {
            if (handler.language != .sla) continue;
            if (bodyUsesIdentifier(handler.body, "target_value_i64") or std.mem.indexOf(u8, handler.body, "sax_event_target_value_i64") != null) return true;
        }
        return false;
    }

    fn emitSlaEventValueI64Helper(self: *SaxLowerer, out: *std.ArrayList(u8)) !void {
        _ = self;
        try out.writer().writeAll(
            \\@sax_event_target_value_i64() -> i64:
            \\L_ENTRY:
            \\  target_value_buf = stack_alloc 32
            \\  target_value_len = call @sax_event_target_value(*target_value_buf, 32)
            \\  target_value_has_3 = gt target_value_len, 2
            \\  br target_value_has_3 -> L_SLA_TARGET_VALUE_I64_3, L_SLA_TARGET_VALUE_I64_CHECK_2
            \\
            \\L_SLA_TARGET_VALUE_I64_CHECK_2:
            \\  target_value_has_2 = gt target_value_len, 1
            \\  br target_value_has_2 -> L_SLA_TARGET_VALUE_I64_2, L_SLA_TARGET_VALUE_I64_CHECK_1
            \\
            \\L_SLA_TARGET_VALUE_I64_CHECK_1:
            \\  target_value_has_1 = gt target_value_len, 0
            \\  br target_value_has_1 -> L_SLA_TARGET_VALUE_I64_1, L_SLA_TARGET_VALUE_I64_0
            \\
            \\L_SLA_TARGET_VALUE_I64_0:
            \\  return 0
            \\
            \\L_SLA_TARGET_VALUE_I64_1:
            \\  target_value_b0 = load target_value_buf+0 as u8
            \\  target_value_d0 = zext target_value_b0 as i64
            \\  target_value_d0 = sub target_value_d0, 48
            \\  return target_value_d0
            \\
            \\L_SLA_TARGET_VALUE_I64_2:
            \\  target_value_b0_2 = load target_value_buf+0 as u8
            \\  target_value_d0_2 = zext target_value_b0_2 as i64
            \\  target_value_d0_2 = sub target_value_d0_2, 48
            \\  target_value_b1 = load target_value_buf+1 as u8
            \\  target_value_d1 = zext target_value_b1 as i64
            \\  target_value_d1 = sub target_value_d1, 48
            \\  target_value_result_2 = mul target_value_d0_2, 10
            \\  target_value_result_2 = add target_value_result_2, target_value_d1
            \\  return target_value_result_2
            \\
            \\L_SLA_TARGET_VALUE_I64_3:
            \\  target_value_b0_3 = load target_value_buf+0 as u8
            \\  target_value_d0_3 = zext target_value_b0_3 as i64
            \\  target_value_d0_3 = sub target_value_d0_3, 48
            \\  target_value_b1_3 = load target_value_buf+1 as u8
            \\  target_value_d1_3 = zext target_value_b1_3 as i64
            \\  target_value_d1_3 = sub target_value_d1_3, 48
            \\  target_value_b2 = load target_value_buf+2 as u8
            \\  target_value_d2 = zext target_value_b2 as i64
            \\  target_value_d2 = sub target_value_d2, 48
            \\  target_value_result_3 = mul target_value_d0_3, 100
            \\  target_value_tens = mul target_value_d1_3, 10
            \\  target_value_result_3 = add target_value_result_3, target_value_tens
            \\  target_value_result_3 = add target_value_result_3, target_value_d2
            \\  return target_value_result_3
            \\
            \\
        );
    }

    fn emitHandler(self: *SaxLowerer, out: *std.ArrayList(u8), handler: parser.Handler) !void {
        const compiled_body = if (handler.language == .sla) try self.compileSlaHandlerBody(handler) else null;
        defer if (compiled_body) |body| self.allocator.free(body);
        const body = compiled_body orelse handler.body;
        const export_name = try self.handlerExportName(handler.name);
        defer self.allocator.free(export_name);
        const impl_name = try self.handlerImplName(handler.name);
        defer self.allocator.free(impl_name);
        const ctx_state_name = try self.ctxStateOffsetConstName();
        defer self.allocator.free(ctx_state_name);
        const ctx_dom_name = try self.ctxDomOffsetConstName();
        defer self.allocator.free(ctx_dom_name);
        try out.writer().print("@export {s}(ctx: ptr):\nL_ENTRY:\n  call @{s}(ctx)\n  return\n\n", .{ export_name, impl_name });
        try out.writer().print("@ffi_wrapper {s}(ctx: ptr):\n", .{impl_name});
        try out.writer().print("L_ENTRY:\n  state = load ctx+{s} as ptr\n  dom = load ctx+{s} as ptr\n", .{ ctx_state_name, ctx_dom_name });
        if (handler.language == .sla) try self.emitSlaEventAmbientPrelude(out, handler.name, body);
        try self.emitHandlerBody(out, body);
        try out.writer().writeByte('\n');
    }

    fn refCallbackHandlerName(self: *const SaxLowerer, attr: parser.Attribute) LowerError!?[]const u8 {
        if (!isRefAttr(attr.name)) return null;
        const expr = switch (attr.value) {
            .interpolation => |expr| expr,
            else => return LowerError.InvalidInterpolation,
        };
        const name = simpleStateExprName(expr) orelse return LowerError.InvalidInterpolation;
        if (self.stateVar(name)) |_| return null;
        if (self.event_handlers.get(name) == null) return LowerError.UnknownHandler;
        return name;
    }

    fn emitRefCallbackCall(self: *const SaxLowerer, out: *std.ArrayList(u8), handler_name: []const u8, kind: RefCallbackKind, ctx_var: []const u8, ref_value: []const u8) !void {
        const impl_name = try self.refCallbackImplName(handler_name, kind);
        defer self.allocator.free(impl_name);
        try out.writer().print("  call @{s}({s}, {s})\n", .{ impl_name, ctx_var, ref_value });
    }

    fn nodeUsesRefCallback(self: *const SaxLowerer, node: parser.DomNode, handler_name: []const u8, kind: RefCallbackKind) bool {
        if ((kind == .component) != node.is_user_component) return false;
        for (node.attrs) |attr| {
            const maybe_name = self.refCallbackHandlerName(attr) catch return false;
            const name = maybe_name orelse continue;
            if (std.mem.eql(u8, name, handler_name)) return true;
        }
        return false;
    }

    fn handlerUsedAsEvent(self: *const SaxLowerer, handler_name: []const u8) bool {
        for (self.component.dom_nodes) |node| {
            for (node.attrs) |attr| {
                if (!attr.is_event) continue;
                const event_handler = attr.event_handler orelse continue;
                if (std.mem.eql(u8, event_handler, handler_name)) return true;
            }
        }
        return false;
    }

    fn handlerUsesRefValue(handler: parser.Handler) bool {
        return std.mem.indexOf(u8, handler.body, "ref_value") != null;
    }

    fn handlerUsedAsRefCallback(self: *const SaxLowerer, handler_name: []const u8) bool {
        for (self.component.dom_nodes) |node| {
            if (self.nodeUsesRefCallback(node, handler_name, .dom)) return true;
            if (self.nodeUsesRefCallback(node, handler_name, .component)) return true;
        }
        return false;
    }

    fn shouldEmitPlainHandler(self: *const SaxLowerer, handler: parser.Handler) bool {
        if (!handlerUsesRefValue(handler)) return true;
        if (self.handlerUsedAsEvent(handler.name)) return true;
        return !self.handlerUsedAsRefCallback(handler.name);
    }

    fn emitRefCallbackHandler(self: *SaxLowerer, out: *std.ArrayList(u8), handler: parser.Handler, kind: RefCallbackKind) !void {
        const compiled_body = if (handler.language == .sla) try self.compileSlaHandlerBody(handler) else null;
        defer if (compiled_body) |body| self.allocator.free(body);
        const body = compiled_body orelse handler.body;
        const impl_name = try self.refCallbackImplName(handler.name, kind);
        defer self.allocator.free(impl_name);
        const ctx_state_name = try self.ctxStateOffsetConstName();
        defer self.allocator.free(ctx_state_name);
        const ctx_dom_name = try self.ctxDomOffsetConstName();
        defer self.allocator.free(ctx_dom_name);
        const ref_ty = switch (kind) {
            .dom => "i64",
            .component => "ptr",
        };

        try out.writer().print("@ffi_wrapper {s}(ctx: ptr, ref_value: {s}):\n", .{ impl_name, ref_ty });
        try out.writer().print("L_ENTRY:\n  state = load ctx+{s} as ptr\n  dom = load ctx+{s} as ptr\n", .{ ctx_state_name, ctx_dom_name });
        try self.emitHandlerBody(out, body);
        try out.writer().writeByte('\n');
    }

    fn emitRefCallbackHandlers(self: *SaxLowerer, out: *std.ArrayList(u8)) !void {
        for (self.component.handlers) |handler| {
            var uses_dom = false;
            var uses_component = false;
            for (self.component.dom_nodes) |node| {
                uses_dom = uses_dom or self.nodeUsesRefCallback(node, handler.name, .dom);
                uses_component = uses_component or self.nodeUsesRefCallback(node, handler.name, .component);
            }
            if (uses_dom) try self.emitRefCallbackHandler(out, handler, .dom);
            if (uses_component) try self.emitRefCallbackHandler(out, handler, .component);
        }
    }

    fn emitHandlerBody(self: *SaxLowerer, out: *std.ArrayList(u8), body: []const u8) !void {
        var lines = std.mem.splitScalar(u8, body, '\n');
        var emitted_entry = false;
        while (lines.next()) |line| {
            const trimmed = std.mem.trimRight(u8, line, "\r");
            if (trimmed.len == 0) continue;
            if (!emitted_entry and std.mem.eql(u8, trimmed, "L_ENTRY:")) {
                emitted_entry = true;
                continue;
            }
            if (std.mem.containsAtLeast(u8, trimmed, 1, "call @render()")) {
                try self.emitRenderAfterWrites(out, body, true);
                continue;
            }
            try out.writer().print("{s}\n", .{trimmed});
        }
    }

    fn emitLifecycleHook(self: *SaxLowerer, out: *std.ArrayList(u8), hook: parser.LifecycleHook) !void {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        const export_name = try std.fmt.allocPrint(self.allocator, "sax_{s}_{s}", .{ stem, hook.name });
        defer self.allocator.free(export_name);
        const impl_name = try self.lifecycleImplName(hook.name);
        defer self.allocator.free(impl_name);
        const ctx_state_name = try self.ctxStateOffsetConstName();
        defer self.allocator.free(ctx_state_name);
        const ctx_dom_name = try self.ctxDomOffsetConstName();
        defer self.allocator.free(ctx_dom_name);

        try out.writer().print("@export {s}(ctx: ptr):\nL_ENTRY:\n  call @{s}(ctx)\n  return\n\n", .{ export_name, impl_name });
        try out.writer().print("@ffi_wrapper {s}(ctx: ptr):\n", .{impl_name});
        try out.writer().print("L_ENTRY:\n  state = load ctx+{s} as ptr\n  dom = load ctx+{s} as ptr\n", .{ ctx_state_name, ctx_dom_name });
        var lines = std.mem.splitScalar(u8, hook.body, '\n');
        var emitted_entry = false;
        while (lines.next()) |line| {
            const trimmed = std.mem.trimRight(u8, line, "\r");
            if (trimmed.len == 0) continue;
            if (!emitted_entry and std.mem.eql(u8, trimmed, "L_ENTRY:")) {
                emitted_entry = true;
                continue;
            }
            if (std.mem.containsAtLeast(u8, trimmed, 1, "call @render()")) {
                try self.emitRenderAfterWrites(out, hook.body, true);
                continue;
            }
            if (std.mem.startsWith(u8, trimmed, "id = call @sax_set_interval(^")) {
                const open = std.mem.indexOfScalar(u8, trimmed, '^') orelse return LowerError.UnknownHandler;
                const close = std.mem.indexOfScalarPos(u8, trimmed, open + 1, ',') orelse return LowerError.UnknownHandler;
                const handler_name = std.mem.trim(u8, trimmed[open + 1 .. close], " ");
                if (self.event_handlers.get(handler_name) == null) return LowerError.UnknownHandler;
                const handler_export = try self.handlerExportName(handler_name);
                defer self.allocator.free(handler_export);
                const handler_idx = try self.string_pool.add(handler_export);
                const handler_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, handler_idx });
                defer self.allocator.free(handler_const);
                const delay_start = std.mem.indexOf(u8, trimmed, ",") orelse return LowerError.UnknownHandler;
                const delay = std.mem.trim(u8, trimmed[delay_start + 1 .. trimmed.len - 1], " ");
                try out.writer().print("  id = call @sax_set_interval(*{s}, {}, {s})\n", .{ handler_const, handler_export.len, delay });
                continue;
            }
            if (std.mem.startsWith(u8, trimmed, "id = call @sax_set_timeout(^")) {
                const open = std.mem.indexOfScalar(u8, trimmed, '^') orelse return LowerError.UnknownHandler;
                const close = std.mem.indexOfScalarPos(u8, trimmed, open + 1, ',') orelse return LowerError.UnknownHandler;
                const handler_name = std.mem.trim(u8, trimmed[open + 1 .. close], " ");
                if (self.event_handlers.get(handler_name) == null) return LowerError.UnknownHandler;
                const handler_export = try self.handlerExportName(handler_name);
                defer self.allocator.free(handler_export);
                const handler_idx = try self.string_pool.add(handler_export);
                const handler_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, handler_idx });
                defer self.allocator.free(handler_const);
                const delay_start = std.mem.indexOf(u8, trimmed, ",") orelse return LowerError.UnknownHandler;
                const delay = std.mem.trim(u8, trimmed[delay_start + 1 .. trimmed.len - 1], " ");
                try out.writer().print("  id = call @sax_set_timeout(*{s}, {}, {s})\n", .{ handler_const, handler_export.len, delay });
                continue;
            }
            try out.writer().print("{s}\n", .{trimmed});
        }
        try out.writer().writeByte('\n');
    }

    fn emitLifecycleDispatch(self: *const SaxLowerer, out: *std.ArrayList(u8), hook_name: []const u8) !void {
        for (self.component.lifecycle_hooks) |hook| {
            if (std.mem.eql(u8, hook.name, hook_name)) {
                const impl_name = try self.lifecycleImplName(hook_name);
                defer self.allocator.free(impl_name);
                try out.writer().print("  call @{s}(ctx)\n", .{impl_name});
                return;
            }
        }
    }

    fn emitRenderTrigger(self: *const SaxLowerer, out: *std.ArrayList(u8), include_update: bool) !void {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        try out.writer().print("  call @sax_{s}_render(ctx)\n", .{stem});
        if (include_update) try self.emitLifecycleDispatch(out, "onUpdate");
    }

    fn stateSlotName(self: *const SaxLowerer, state_name: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "{s}_{s}", .{ self.component.name, state_name });
    }

    fn lineStoresState(self: *const SaxLowerer, line: []const u8, state_name: []const u8) !bool {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, "store state+")) return false;
        const slot_name = try self.stateSlotName(state_name);
        defer self.allocator.free(slot_name);
        const rest = trimmed["store state+".len..];
        if (!std.mem.startsWith(u8, rest, slot_name)) return false;
        if (rest.len == slot_name.len) return true;
        const next = rest[slot_name.len];
        return std.ascii.isWhitespace(next) or next == ',' or next == '+' or next == '-' or next == '(' or next == ')';
    }

    fn collectWrittenStates(self: *const SaxLowerer, body: []const u8) !std.StringHashMap(void) {
        var writes = std.StringHashMap(void).init(self.allocator);
        errdefer writes.deinit();

        var lines = std.mem.splitScalar(u8, body, '\n');
        while (lines.next()) |line| {
            for (self.component.state_vars) |sv| {
                if (try self.lineStoresState(line, sv.name)) {
                    try writes.put(sv.name, {});
                    if (std.mem.endsWith(u8, sv.name, "_len")) {
                        const base_name = sv.name[0 .. sv.name.len - "_len".len];
                        if (self.stateVar(base_name)) |base| {
                            if (base.ty == .ptr) try writes.put(base.name, {});
                        }
                    }
                }
            }
        }

        return writes;
    }

    fn nodeUsesState(node: parser.DomNode, state_name: []const u8) bool {
        for (node.attrs) |attr| {
            if (isRefAttr(attr.name) or isKeyAttr(attr.name)) continue;
            if (isDefaultOnlyFormAttr(attr.name)) continue;
            switch (attr.value) {
                .literal => {},
                .interpolation => |expr| {
                    for (expr.deps) |dep| {
                        if (std.mem.eql(u8, dep, state_name)) return true;
                    }
                },
                .template => |pieces| {
                    for (pieces) |piece| switch (piece) {
                        .text => {},
                        .interpolation => |expr| {
                            for (expr.deps) |dep| {
                                if (std.mem.eql(u8, dep, state_name)) return true;
                            }
                        },
                        .json_string_interpolation => |expr| {
                            for (expr.deps) |dep| {
                                if (std.mem.eql(u8, dep, state_name)) return true;
                            }
                        },
                        .json_object_spread => |spread| {
                            for (spread.expr.deps) |dep| {
                                if (std.mem.eql(u8, dep, state_name)) return true;
                            }
                        },
                    };
                },
            }
        }
        for (node.children) |child| {
            switch (child) {
                .text => |piece| switch (piece) {
                    .text => {},
                    .interpolation => |expr| {
                        for (expr.deps) |dep| {
                            if (std.mem.eql(u8, dep, state_name)) return true;
                        }
                    },
                    .json_string_interpolation => |expr| {
                        for (expr.deps) |dep| {
                            if (std.mem.eql(u8, dep, state_name)) return true;
                        }
                    },
                    .json_object_spread => |spread| {
                        for (spread.expr.deps) |dep| {
                            if (std.mem.eql(u8, dep, state_name)) return true;
                        }
                    },
                },
                .node_index => {},
            }
        }
        return false;
    }

    fn emitSelectiveRender(self: *SaxLowerer, out: *std.ArrayList(u8), writes: *std.StringHashMap(void)) !void {
        var emitted_any = false;
        for (self.component.dom_nodes, 0..) |node, idx| {
            var should_update = writes.count() == 0;
            if (!should_update) {
                for (self.component.state_vars) |sv| {
                    if (!writes.contains(sv.name)) continue;
                    if (SaxLowerer.nodeUsesState(node, sv.name)) {
                        should_update = true;
                        break;
                    }
                }
            }
            if (!should_update) continue;
            try self.emitNodeRender(out, "ctx", idx);
            emitted_any = true;
        }
        if (!emitted_any) {
            for (self.component.dom_nodes, 0..) |_, idx| {
                try self.emitNodeRender(out, "ctx", idx);
            }
        }
    }

    fn emitRenderAfterWrites(self: *SaxLowerer, out: *std.ArrayList(u8), body: []const u8, include_update: bool) !void {
        var writes = try self.collectWrittenStates(body);
        defer writes.deinit();
        try self.emitSelectiveRender(out, &writes);
        if (include_update) try self.emitLifecycleDispatch(out, "onUpdate");
    }

    fn emitConstructBody(self: *SaxLowerer, out: *std.ArrayList(u8), parent_var: []const u8) !void {
        const state_size_name = try self.stateSizeConstName();
        defer self.allocator.free(state_size_name);
        const dom_size_name = try self.domSizeConstName();
        defer self.allocator.free(dom_size_name);
        const ctx_size_name = try self.ctxSizeConstName();
        defer self.allocator.free(ctx_size_name);
        const ctx_state_name = try self.ctxStateOffsetConstName();
        defer self.allocator.free(ctx_state_name);
        const ctx_dom_name = try self.ctxDomOffsetConstName();
        defer self.allocator.free(ctx_dom_name);

        try out.writer().print("  state = alloc {s}\n", .{state_size_name});
        for (self.component.state_vars, 0..) |sv, idx| {
            switch (sv.ty) {
                .ptr => {
                    const init_expr = std.mem.trim(u8, sv.init_expr, " \t\r");
                    if (std.mem.startsWith(u8, init_expr, "alloc ")) {
                        const sz = std.mem.trim(u8, init_expr["alloc ".len..], " \t\r");
                        try out.writer().print("  tmp_ptr_{d} = alloc {s}\n", .{ idx, sz });
                        const slot_name = try self.stateSlotConstName(sv.name);
                        defer self.allocator.free(slot_name);
                        try out.writer().print("  store state+{s}, tmp_ptr_{d} as ptr\n", .{ slot_name, idx });
                    } else if (parseStaticStringLiteral(stateInitValueExpr(sv.init_expr, sv.ty))) |literal| {
                        const literal_idx = try self.string_pool.add(literal);
                        const literal_const = try std.fmt.allocPrint(self.allocator, "sax_{s}_{d}", .{ self.component.name, literal_idx });
                        defer self.allocator.free(literal_const);
                        const slot_name = try self.stateSlotConstName(sv.name);
                        defer self.allocator.free(slot_name);
                        // Ptr state initialized from a static string literal must still accept
                        // later prop writes that are longer than the default literal.
                        // Use the same small owned-string floor as explicit `alloc 32` state
                        // unless the literal is already longer.
                        const alloc_size = @max(literal.len, @as(usize, 32));
                        try out.writer().print("  tmp_ptr_{d} = alloc {}\n", .{ idx, alloc_size });
                        try out.writer().print("  call @sax_mem_copy(*tmp_ptr_{d}, *{s}, {})\n", .{ idx, literal_const, literal.len });
                        try out.writer().print("  store state+{s}, tmp_ptr_{d} as ptr\n", .{ slot_name, idx });
                    } else {
                        const slot_name = try self.stateSlotConstName(sv.name);
                        defer self.allocator.free(slot_name);
                        try out.writer().print("  store state+{s}, 0 as ptr\n", .{slot_name});
                    }
                },
                .f64 => {
                    const slot_name = try self.stateSlotConstName(sv.name);
                    defer self.allocator.free(slot_name);
                    try out.writer().print("  store state+{s}, {d} as i64\n", .{ slot_name, try f64BitsLiteral(sv.init_expr, sv.ty) });
                },
                else => {
                    const slot_name = try self.stateSlotConstName(sv.name);
                    defer self.allocator.free(slot_name);
                    try out.writer().print("  store state+{s}, {s} as {s}\n", .{ slot_name, stateInitValueExpr(sv.init_expr, sv.ty), stateTypeName(sv.ty) });
                },
            }
        }

        try out.writer().print("  dom = alloc {s}\n", .{dom_size_name});
        try out.writer().print("  ctx = alloc {s}\n", .{ctx_size_name});
        try out.writer().print("  store ctx+{s}, state as ptr\n", .{ctx_state_name});
        try out.writer().print("  store ctx+{s}, dom as ptr\n", .{ctx_dom_name});

        for (self.component.dom_nodes, 0..) |_, idx| {
            try self.emitNodeInit(out, "ctx", idx);
        }
        for (self.component.dom_nodes, 0..) |_, idx| {
            try self.emitNodeAttachChildren(out, idx);
        }
        try self.emitDeferredInitialFormValuesAfterAttach(out);
        for (self.component.root_nodes) |root_idx| {
            const root_node = self.component.dom_nodes[root_idx];
            if (root_node.is_user_component) {
                try self.emitUserComponentMount(out, root_idx, parent_var, "ctx", null, null, false);
            } else {
                const root_var = try std.fmt.allocPrint(self.allocator, "node_{d}", .{root_idx});
                defer self.allocator.free(root_var);
                try out.writer().print("  call @sax_dom_append_child({s}, {s})\n", .{ parent_var, root_var });
            }
        }
        try self.emitAutofocusAfterMount(out);
        try self.emitRenderTrigger(out, false);
        try self.emitLifecycleDispatch(out, "onMount");
    }

    fn emitInit(self: *SaxLowerer, out: *std.ArrayList(u8)) !void {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        const impl_name = try self.initImplName();
        defer self.allocator.free(impl_name);
        try out.writer().print("@export sax_{s}_init() -> ptr:\nL_ENTRY:\n  ctx = call @{s}()\n  return ctx\n\n", .{ stem, impl_name });
        try out.writer().print("@ffi_wrapper {s}() -> ptr:\nL_ENTRY:\n", .{impl_name});
        const host_selector = try self.hostSelectorConstName();
        defer self.allocator.free(host_selector);
        try out.writer().print("  host = call @sax_dom_query(*{s}, 4)\n", .{host_selector});
        try self.emitConstructBody(out, "host");
        try out.writer().writeAll("  return ctx\n\n");
    }

    fn emitMount(self: *SaxLowerer, out: *std.ArrayList(u8)) !void {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        const impl_name = try self.mountImplName();
        defer self.allocator.free(impl_name);
        try out.writer().print("@export sax_{s}_mount(parent_h: i64) -> ptr:\nL_ENTRY:\n  ctx = call @{s}(parent_h)\n  return ctx\n\n", .{ stem, impl_name });
        try out.writer().print("@ffi_wrapper {s}(parent_h: i64) -> ptr:\nL_ENTRY:\n", .{impl_name});
        try self.emitConstructBody(out, "parent_h");
        try out.writer().writeAll("  return ctx\n\n");
    }

    fn slotNodeIndex(self: *const SaxLowerer) ?usize {
        for (self.component.dom_nodes, 0..) |node, idx| {
            if (std.mem.eql(u8, node.tag, "Slot")) return idx;
        }
        if (self.component.root_nodes.len != 0) return self.component.root_nodes[0];
        return null;
    }

    fn rootNodeIndex(self: *const SaxLowerer) ?usize {
        if (self.component.root_nodes.len != 0) return self.component.root_nodes[0];
        return null;
    }

    fn emitSlot(self: *const SaxLowerer, out: *std.ArrayList(u8)) !void {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        const impl_name = try self.slotImplName();
        defer self.allocator.free(impl_name);
        const ctx_dom_name = try self.ctxDomOffsetConstName();
        defer self.allocator.free(ctx_dom_name);
        try out.writer().print("@export sax_{s}_slot(ctx: ptr) -> i64:\nL_ENTRY:\n  slot_h = call @{s}(ctx)\n  return slot_h\n\n", .{ stem, impl_name });
        try out.writer().print("@ffi_wrapper {s}(ctx: ptr) -> i64:\nL_ENTRY:\n", .{impl_name});
        try out.writer().print("  dom = load ctx+{s} as ptr\n", .{ctx_dom_name});
        if (self.slotNodeIndex()) |idx| {
            const node = self.component.dom_nodes[idx];
            const node_slot = try self.nodeSlotConstName(node.alias);
            defer self.allocator.free(node_slot);
            try out.writer().print("  slot_h = load dom+{s} as i64\n", .{node_slot});
            try out.writer().writeAll("  return slot_h\n\n");
        } else {
            try out.writer().writeAll("  return 0\n\n");
        }
    }

    fn emitRoot(self: *const SaxLowerer, out: *std.ArrayList(u8)) !void {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        const impl_name = try self.rootImplName();
        defer self.allocator.free(impl_name);
        const ctx_dom_name = try self.ctxDomOffsetConstName();
        defer self.allocator.free(ctx_dom_name);

        try out.writer().print("@export sax_{s}_root(ctx: ptr) -> i64:\nL_ENTRY:\n  root_h = call @{s}(ctx)\n  return root_h\n\n", .{ stem, impl_name });
        try out.writer().print("@ffi_wrapper {s}(ctx: ptr) -> i64:\nL_ENTRY:\n", .{impl_name});
        try out.writer().print("  dom = load ctx+{s} as ptr\n", .{ctx_dom_name});
        if (self.rootNodeIndex()) |idx| {
            const node = self.component.dom_nodes[idx];
            const node_slot = try self.nodeSlotConstName(node.alias);
            defer self.allocator.free(node_slot);
            if (node.is_user_component) {
                const child_stem = try self.componentExportStem(node.tag);
                defer self.allocator.free(child_stem);
                try out.writer().print("  child_ctx = load dom+{s} as ptr\n", .{node_slot});
                try out.writer().print("  root_h = call @sax_{s}_root(child_ctx)\n", .{child_stem});
            } else {
                try out.writer().print("  root_h = load dom+{s} as i64\n", .{node_slot});
            }
            try out.writer().writeAll("  return root_h\n\n");
        } else {
            try out.writer().writeAll("  return 0\n\n");
        }
    }

    fn emitStateSetter(self: *const SaxLowerer, out: *std.ArrayList(u8), sv: parser.StateVar) !void {
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        const ctx_state_name = try self.ctxStateOffsetConstName();
        defer self.allocator.free(ctx_state_name);
        const slot_name = try self.stateSlotConstName(sv.name);
        defer self.allocator.free(slot_name);

        if (sv.ty == .ptr) {
            const impl_name = try self.stringStateSetterImplName(sv.name);
            defer self.allocator.free(impl_name);
            try out.writer().print("@export sax_{s}_set_{s}_str(ctx: ptr, src: ptr, len: i64):\nL_ENTRY:\n  call @{s}(ctx, src, len)\n  return\n\n", .{ stem, sv.name, impl_name });
            try out.writer().print("@ffi_wrapper {s}(ctx: ptr, src: ptr, len: i64):\nL_ENTRY:\n", .{impl_name});
            try out.writer().print("  state = load ctx+{s} as ptr\n", .{ctx_state_name});
            try out.writer().print("  dst = load state+{s} as ptr\n", .{slot_name});
            try out.writer().writeAll("  call @sax_mem_copy(*dst, *src, len)\n");
            const len_name = try self.stateLenVarName(sv.name);
            defer self.allocator.free(len_name);
            if (self.stateVar(len_name)) |_| {
                const len_slot = try self.stateSlotConstName(len_name);
                defer self.allocator.free(len_slot);
                try out.writer().print("  store state+{s}, len as i64\n", .{len_slot});
            }
            try out.writer().print("  call @sax_{s}_render(ctx)\n", .{stem});
            try out.writer().writeAll("  return\n\n");
            return;
        }

        const impl_name = try self.stateSetterImplName(sv.name);
        defer self.allocator.free(impl_name);

        try out.writer().print("@export sax_{s}_set_{s}(ctx: ptr, value: i64):\nL_ENTRY:\n  call @{s}(ctx, value)\n  return\n\n", .{ stem, sv.name, impl_name });
        try out.writer().print("@ffi_wrapper {s}(ctx: ptr, value: i64):\nL_ENTRY:\n", .{impl_name});
        try out.writer().print("  state = load ctx+{s} as ptr\n", .{ctx_state_name});
        switch (sv.ty) {
            .i64 => try out.writer().print("  store state+{s}, value as i64\n", .{slot_name}),
            .i32 => try out.writer().print("  narrowed = trunc value as i32\n  store state+{s}, narrowed as i32\n", .{slot_name}),
            .i1 => try out.writer().print("  is_set = ne value, 0\n  store state+{s}, is_set as i1\n", .{slot_name}),
            .f64 => try out.writer().print("  store state+{s}, value as i64\n", .{slot_name}),
            .ptr => unreachable,
        }
        try out.writer().print("  call @sax_{s}_render(ctx)\n", .{stem});
        try out.writer().writeAll("  return\n\n");
    }

    fn emitStateSetters(self: *const SaxLowerer, out: *std.ArrayList(u8)) !void {
        for (self.component.state_vars) |sv| {
            try self.emitStateSetter(out, sv);
        }
    }

    fn emitRender(self: *SaxLowerer, out: *std.ArrayList(u8)) !void {
        const ctx_state_name = try self.ctxStateOffsetConstName();
        defer self.allocator.free(ctx_state_name);
        const ctx_dom_name = try self.ctxDomOffsetConstName();
        defer self.allocator.free(ctx_dom_name);

        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        const impl_name = try self.renderImplName();
        defer self.allocator.free(impl_name);
        try out.writer().print("@export sax_{s}_render(ctx: ptr):\nL_ENTRY:\n  call @{s}(ctx)\n  return\n\n", .{ stem, impl_name });
        try out.writer().print("@ffi_wrapper {s}(ctx: ptr):\nL_ENTRY:\n", .{impl_name});
        try out.writer().print("  state = load ctx+{s} as ptr\n", .{ctx_state_name});
        try out.writer().print("  dom = load ctx+{s} as ptr\n", .{ctx_dom_name});
        for (self.component.dom_nodes, 0..) |_, idx| {
            try self.emitNodeRender(out, "ctx", idx);
        }
        try out.writer().writeAll("  return\n\n");
    }

    fn emitRefCallbackUnmount(self: *const SaxLowerer, out: *std.ArrayList(u8), node: parser.DomNode) !void {
        const kind: RefCallbackKind = if (node.is_user_component) .component else .dom;
        for (node.attrs) |attr| {
            const maybe_name = try self.refCallbackHandlerName(attr);
            const handler_name = maybe_name orelse continue;
            try self.emitRefCallbackCall(out, handler_name, kind, "ctx", "0");
        }
    }

    fn emitTextNodeDestroy(self: *const SaxLowerer, out: *std.ArrayList(u8), idx: usize) !void {
        const slot = self.node_slots[idx];
        if (slot.text_slot_count == 0) return;
        const node = self.component.dom_nodes[idx];
        var text_idx: usize = 0;
        while (text_idx < slot.text_slot_count) : (text_idx += 1) {
            const text_slot_name = try self.textNodeSlotConstName(node.alias, text_idx);
            defer self.allocator.free(text_slot_name);
            const text_var = try std.fmt.allocPrint(self.allocator, "text_node_destroy_{d}_{d}", .{ idx, text_idx });
            defer self.allocator.free(text_var);
            try out.writer().print("  {s} = load dom+{s} as i64\n", .{ text_var, text_slot_name });
            try out.writer().print("  call @sax_dom_remove_self({s})\n", .{text_var});
        }
    }

    fn emitDestroy(self: *const SaxLowerer, out: *std.ArrayList(u8)) !void {
        const ctx_state_name = try self.ctxStateOffsetConstName();
        defer self.allocator.free(ctx_state_name);
        const ctx_dom_name = try self.ctxDomOffsetConstName();
        defer self.allocator.free(ctx_dom_name);

        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        const impl_name = try self.destroyImplName();
        defer self.allocator.free(impl_name);
        try out.writer().print("@export sax_{s}_destroy(ctx: ptr):\nL_ENTRY:\n  call @{s}(ctx)\n  return\n\n", .{ stem, impl_name });
        try out.writer().print("@ffi_wrapper {s}(ctx: ptr):\nL_ENTRY:\n", .{impl_name});
        try out.writer().print("  state = load ctx+{s} as ptr\n", .{ctx_state_name});
        try out.writer().print("  dom = load ctx+{s} as ptr\n", .{ctx_dom_name});
        try self.emitLifecycleDispatch(out, "onUnmount");
        for (self.component.dom_nodes, 0..) |node, idx| {
            try self.emitRefCallbackUnmount(out, node);
            try self.emitTextNodeDestroy(out, idx);
            const node_slot = try self.nodeSlotConstName(node.alias);
            defer self.allocator.free(node_slot);
            const node_var = try std.fmt.allocPrint(self.allocator, "node_{d}", .{idx});
            defer self.allocator.free(node_var);
            try out.writer().print("  {s} = load dom+{s} as ptr\n", .{ node_var, node_slot });
            if (node.is_user_component) {
                const child_stem = try self.componentExportStem(node.tag);
                defer self.allocator.free(child_stem);
                try out.writer().print("  call @sax_{s}_destroy({s})\n", .{ child_stem, node_var });
            } else {
                try out.writer().print("  call @sax_dom_remove_self({s})\n", .{node_var});
            }
            try out.writer().print("  !{s}\n", .{node_var});
        }
        for (self.component.release_vars) |release_name| {
            try self.emitLoadState(out, release_name, release_name);
            try out.writer().print("  !{s}\n", .{release_name});
        }
        if (componentHasSlaHandlers(self.component)) {
            for (self.component.state_vars) |sv| {
                if (releaseListContains(self.component.release_vars, sv.name)) continue;
                try self.emitLoadState(out, sv.name, sv.name);
                try out.writer().print("  !{s}\n", .{sv.name});
            }
        }
        try out.writer().writeAll("  !dom\n  !state\n  !ctx\n");
        try out.writer().writeAll("  return\n\n");
    }

    fn emitRouterInit(self: *const SaxLowerer, out: *std.ArrayList(u8)) !void {
        if (self.component.route_pages.len == 0) return;
        const stem = try self.componentStem();
        defer self.allocator.free(stem);
        const router_path_name = try std.fmt.allocPrint(self.allocator, "sax_{s}_route_path", .{self.component.name});
        defer self.allocator.free(router_path_name);

        const impl_name = try self.routerInitImplName();
        defer self.allocator.free(impl_name);
        try out.writer().print("@export sax_{s}_router_init(path: ptr):\nL_ENTRY:\n  call @{s}(path)\n  return\n\n", .{ stem, impl_name });
        try out.writer().print("@ffi_wrapper {s}(path: ptr):\nL_ENTRY:\n", .{impl_name});
        try out.writer().print("  call @sax_router_replace(*{s}, {})\n", .{ router_path_name, self.component.route_pages[0].path.len });
        try out.writer().print("  call @sax_router_init(*{s}, {})\n", .{ router_path_name, self.component.route_pages[0].path.len });
        try out.writer().writeAll("  return\n\n");
    }

    pub fn lower(self: *SaxLowerer, out: *std.ArrayList(u8), options: LowerOptions) !void {
        const shared_mode = options.shared_decls orelse if (options.emit_shared_decls) SharedDeclMode.full else SharedDeclMode.none;
        if (shared_mode == .runtime_only) {
            try self.appendExternDecls(out);
            try self.appendComponentForwardDecls(out);
            try self.appendStdImports(out);
            try self.appendArrayAdapter(out);
            if (options.emit_app_alias) {
                const root_name = try self.componentStem();
                defer self.allocator.free(root_name);
                if (!std.mem.eql(u8, root_name, "app")) {
                    try out.writer().print("@export sax_app_init() -> ptr:\nL_ENTRY:\n  ctx = call @sax_{s}_init()\n  return ctx\n\n", .{root_name});
                }
            }
            return;
        }

        const state_size_name = try self.stateSizeConstName();
        defer self.allocator.free(state_size_name);
        const dom_size_name = try self.domSizeConstName();
        defer self.allocator.free(dom_size_name);
        const ctx_size_name = try self.ctxSizeConstName();
        defer self.allocator.free(ctx_size_name);
        const ctx_state_name = try self.ctxStateOffsetConstName();
        defer self.allocator.free(ctx_state_name);
        const ctx_dom_name = try self.ctxDomOffsetConstName();
        defer self.allocator.free(ctx_dom_name);

        try out.writer().print("#def {s} = {}\n", .{ state_size_name, self.stateAllocSize() });
        try out.writer().print("#def {s} = {}\n", .{ dom_size_name, self.domAllocSize() });
        try out.writer().print("#def {s} = 16\n", .{ctx_size_name});
        try out.writer().print("#def {s} = +0\n", .{ctx_state_name});
        try out.writer().print("#def {s} = +8\n\n", .{ctx_dom_name});

        for (self.component.state_vars, 0..) |sv, idx| {
            const slot_name = try self.stateSlotConstName(sv.name);
            defer self.allocator.free(slot_name);
            try out.writer().print("#def {s} = +{}\n", .{ slot_name, self.state_slots[idx].offset });
        }
        if (self.component.state_vars.len != 0) try out.writer().writeByte('\n');

        for (self.component.dom_nodes, 0..) |node, idx| {
            const slot_name = try self.nodeSlotConstName(node.alias);
            defer self.allocator.free(slot_name);
            try out.writer().print("#def {s} = +{}\n", .{ slot_name, self.node_slots[idx].handle_slot * 8 });
            const slot = self.node_slots[idx];
            const text_slot_start = slot.text_slot_start orelse continue;
            var text_idx: usize = 0;
            while (text_idx < slot.text_slot_count) : (text_idx += 1) {
                const text_slot_name = try self.textNodeSlotConstName(node.alias, text_idx);
                defer self.allocator.free(text_slot_name);
                try out.writer().print("#def {s} = +{}\n", .{ text_slot_name, (text_slot_start + text_idx) * 8 });
            }
        }
        if (self.component.dom_nodes.len != 0) try out.writer().writeByte('\n');

        switch (shared_mode) {
            .none => {},
            .full => {
                try self.appendExternDecls(out);
                try self.appendComponentForwardDecls(out);
                try self.appendStdImports(out);
                try self.appendArrayAdapter(out);
            },
            .component_externs => {
                try self.appendExternDecls(out);
                try self.appendComponentForwardDecls(out);
            },
            .runtime_only => unreachable,
        }
        try self.emitInit(out);
        try self.emitMount(out);
        try self.emitSlot(out);
        try self.emitRoot(out);
        try self.emitStateSetters(out);
        try self.emitRender(out);
        try self.emitRouterInit(out);
        for (self.component.lifecycle_hooks) |hook| {
            try self.emitLifecycleHook(out, hook);
        }
        if (self.usesSlaEventValueI64()) try self.emitSlaEventValueI64Helper(out);
        for (self.component.handlers) |handler| {
            if (self.shouldEmitPlainHandler(handler)) try self.emitHandler(out, handler);
        }
        try self.emitRefCallbackHandlers(out);
        try self.emitDestroy(out);
        try self.appendConstDecls(out);
    }
};

test "lowerer emits counter-shaped sa for the docs example" {
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

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "#def Counter_count = +0"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "#def Counter_last = +8"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_bind_event"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"click\""));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"onclick\"") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_append_child(host, node_0)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@export sax_counter_inc(ctx: ptr):"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@export sax_counter_render(ctx: ptr):"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@export sax_counter_destroy(ctx: ptr):"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "  return\n\n"));
}

test "lowerer emits lifecycle hooks for docs phase 2 shapes" {
    const source =
        \\<Component name="TimerWidget">
        \\  <state>
        \\    tick = 0
        \\    timer_id = 0
        \\  </state>
        \\  <div><p>Tick: {tick}</p></div>
        \\  @onMount:
        \\  L_ENTRY:
        \\    id = call @sax_set_interval(^onTick, 1000)
        \\    store state+TimerWidget_timer_id, id as i64
        \\    ret
        \\  @onUnmount:
        \\  L_ENTRY:
        \\    id = load state+TimerWidget_timer_id as i64
        \\    call @sax_clear_interval(id)
        \\    ret
        \\  @onTick:
        \\  L_ENTRY:
        \\    tick = load state+TimerWidget_tick as i64
        \\    tick = add tick, 1
        \\    store state+TimerWidget_tick, tick as i64
        \\    call @render()
        \\    ret
        \\  !tick !timer_id
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_set_interval"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_clear_interval"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@export sax_timerwidget_onMount(ctx: ptr):"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@export sax_timerwidget_onUnmount(ctx: ptr):"));
}

test "lowerer dispatches onUnmount before recursive destroy and DOM removal" {
    const source =
        \\<Component name="Parent">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\  <section><Child /><p>{count}</p></section>
        \\  @onUnmount:
        \\  L_ENTRY:
        \\    store state+Parent_count, 99 as i64
        \\    ret
        \\  !count
        \\</Component>
        \\<Component name="Child">
        \\  <state>
        \\    closed = 0 as i1
        \\  </state>
        \\  <span>Child</span>
        \\  @onUnmount:
        \\  L_ENTRY:
        \\    store state+Child_closed, 1 as i1
        \\    ret
        \\  !closed
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    const parent_destroy_start = std.mem.indexOf(u8, out.items, "@ffi_wrapper sax_parent_destroy_ffi(ctx: ptr):") orelse return error.TestUnexpectedResult;
    const parent_destroy_end = std.mem.indexOf(u8, out.items[parent_destroy_start..], "@export sax_parent_set_count(ctx: ptr, value: i64):") orelse out.items.len - parent_destroy_start;
    const parent_destroy = out.items[parent_destroy_start .. parent_destroy_start + parent_destroy_end];

    const parent_unmount_pos = std.mem.indexOf(u8, parent_destroy, "call @sax_parent_onUnmount_ffi(ctx)") orelse return error.TestUnexpectedResult;
    const child_destroy_pos = std.mem.indexOf(u8, parent_destroy, "call @sax_child_destroy(node_1)") orelse return error.TestUnexpectedResult;
    const section_remove_pos = std.mem.indexOf(u8, parent_destroy, "call @sax_dom_remove_self(node_0)") orelse return error.TestUnexpectedResult;
    const section_release_pos = std.mem.indexOf(u8, parent_destroy, "!node_0") orelse return error.TestUnexpectedResult;
    const child_release_pos = std.mem.indexOf(u8, parent_destroy, "!node_1") orelse return error.TestUnexpectedResult;
    try std.testing.expect(parent_unmount_pos < section_remove_pos);
    try std.testing.expect(parent_unmount_pos < child_destroy_pos);
    try std.testing.expect(section_remove_pos < section_release_pos);
    try std.testing.expect(child_destroy_pos < child_release_pos);

    var child_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[1]);
    defer child_lowerer.deinit();

    var child_out = std.ArrayList(u8).init(std.testing.allocator);
    defer child_out.deinit();
    try child_lowerer.lower(&child_out, .{});

    const child_destroy_start = std.mem.indexOf(u8, child_out.items, "@ffi_wrapper sax_child_destroy_ffi(ctx: ptr):") orelse return error.TestUnexpectedResult;
    const child_destroy_end = std.mem.indexOf(u8, child_out.items[child_destroy_start..], "@export sax_child_set_closed(ctx: ptr, value: i64):") orelse child_out.items.len - child_destroy_start;
    const child_destroy = child_out.items[child_destroy_start .. child_destroy_start + child_destroy_end];
    const child_unmount_pos = std.mem.indexOf(u8, child_destroy, "call @sax_child_onUnmount_ffi(ctx)") orelse return error.TestUnexpectedResult;
    const child_dom_remove_pos = std.mem.indexOf(u8, child_destroy, "call @sax_dom_remove_self(node_0)") orelse return error.TestUnexpectedResult;
    const child_dom_release_pos = std.mem.indexOf(u8, child_destroy, "!node_0") orelse return error.TestUnexpectedResult;
    try std.testing.expect(child_unmount_pos < child_dom_remove_pos);
    try std.testing.expect(child_dom_remove_pos < child_dom_release_pos);
}

test "lowerer emits onUpdate after render triggers" {
    const source =
        \\<Component name="Updater">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\  <div><button onclick={^inc}>+</button><p>{count}</p></div>
        \\  @inc:
        \\  L_ENTRY:
        \\    count = load state+Updater_count as i64
        \\    count = add count, 1
        \\    store state+Updater_count, count as i64
        \\    call @render()
        \\    ret
        \\  @onUpdate:
        \\  L_ENTRY:
        \\    call @sax_get_time()
        \\    ret
        \\  !count
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@export sax_updater_onUpdate(ctx: ptr):"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_get_time()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_updater_render(ctx)"));
}

test "lowerer keeps alloc state buffers on the heap" {
    const source =
        \\<Component name="BufferLab">
        \\  <state>
        \\    scratch = alloc 32
        \\    writes = 0
        \\  </state>
        \\  <section><p>{writes}</p></section>
        \\  !scratch !writes
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "tmp_ptr_0 = alloc 32"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "tmp_ptr_0 = stack_alloc 32") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "store state+BufferLab_scratch, tmp_ptr_0 as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "scratch = load state+BufferLab_scratch as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "!scratch"));
}

test "lowerer emits read-only arithmetic for interpolation expressions" {
    const source =
        \\<Component name="ExprLab">
        \\  <state>
        \\    count = 7
        \\    label = 5
        \\  </state>
        \\  <section>
        \\    <p>Total: {count + label * 2}</p>
        \\    <input value="{(count + label * 2) / 3}" />
        \\  </section>
        \\  !count !label
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = load state+ExprLab_count as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = load state+ExprLab_label as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = mul "));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = add "));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = sdiv "));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_itoa("));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "load state+ExprLab_count + label") == null);
}

test "lowerer preserves typed state init and interpolation formatting" {
    const source =
        \\<Component name="TypedLab">
        \\  <state>
        \\    score = 7 as i32
        \\    active = 1 as i1
        \\    ratio = 0.75 as f64
        \\  </state>
        \\  <section>
        \\    <p>{score}</p>
        \\    <p>{active}</p>
        \\    <p>{ratio}</p>
        \\  </section>
        \\  !score !active !ratio
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "store state+TypedLab_score, 7 as i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "store state+TypedLab_active, 1 as i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "store state+TypedLab_ratio, 4604930618986332160 as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = load state+TypedLab_score as i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = sext "));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = load state+TypedLab_active as i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = zext "));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = load state+TypedLab_ratio as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_ftoa_bits("));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "as i32 as i32") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "as i1 as i1") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "as f64 as f64") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "load state+TypedLab_ratio as f64") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "bitcast ") == null);
}

test "lowerer initializes ptr state from static string literals" {
    const source =
        \\<Component name="PtrInitLab">
        \\  <state>
        \\    position = 'bottom' as ptr
        \\    position_len = 6
        \\  </state>
        \\  <div className="{position}">Body</div>
        \\  !position !position_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "tmp_ptr_0 = alloc 32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_mem_copy(*tmp_ptr_0, *sax_PtrInitLab_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "store state+PtrInitLab_position, tmp_ptr_0 as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"bottom\""));
}

test "lowerer gives static ptr state enough capacity for longer later prop writes" {
    const source =
        \\<Component name="PtrCapacityLab">
        \\  <state>
        \\    color = 'primary' as ptr
        \\    color_len = 7
        \\  </state>
        \\  <div>Body</div>
        \\  !color !color_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "tmp_ptr_0 = alloc 32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_mem_copy(*tmp_ptr_0, *sax_PtrCapacityLab_"));
}

test "lowerer emits selective render for state writes" {
    const source =
        \\<Component name="Selective">
        \\  <state>
        \\    count = 0
        \\    label = 0
        \\  </state>
        \\  <div>
        \\    <h1>{count}</h1>
        \\    <p>{label}</p>
        \\  </div>
        \\  @inc:
        \\  L_ENTRY:
        \\    count = load state+Selective_count as i64
        \\    count = add count, 1
        \\    store state+Selective_count, count as i64
        \\    call @render()
        \\    ret
        \\  !count !label
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_selective_render(ctx)"));
    const inc_start = std.mem.indexOf(u8, out.items, "@ffi_wrapper sax_selective_inc_ffi(ctx: ptr):") orelse unreachable;
    const inc_end = std.mem.indexOf(u8, out.items[inc_start..], "@export sax_selective_destroy(ctx: ptr):") orelse out.items.len - inc_start;
    const inc_block = out.items[inc_start .. inc_start + inc_end];
    try std.testing.expect(std.mem.containsAtLeast(u8, inc_block, 1, "call @sax_dom_set_text(node_1, *"));
    try std.testing.expect(std.mem.indexOf(u8, inc_block, "call @sax_dom_set_text(node_2, *") == null);
}

test "lowerer refreshes ptr state text when only its len state is written" {
    const source =
        \\<Component name="PtrLenSelective">
        \\  <state>
        \\    label = alloc 16
        \\    label_len = 0
        \\  </state>
        \\  <p>Label: {label}</p>
        \\  @set:
        \\  L_ENTRY:
        \\    store state+PtrLenSelective_label_len, 4 as i64
        \\    call @render()
        \\    ret
        \\  !label !label_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    const handler_start = std.mem.indexOf(u8, out.items, "@ffi_wrapper sax_ptrlenselective_set_ffi(ctx: ptr):") orelse return error.TestUnexpectedResult;
    const handler_end = std.mem.indexOf(u8, out.items[handler_start..], "@export sax_ptrlenselective_destroy(ctx: ptr):") orelse out.items.len - handler_start;
    const handler_body = out.items[handler_start .. handler_start + handler_end];
    try std.testing.expect(std.mem.containsAtLeast(u8, handler_body, 1, "call @sax_dom_set_text(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, handler_body, 1, "_len = load state+PtrLenSelective_label_len as i64"));
}

test "lowerer emits router metadata and init when pages are present" {
    const source =
        \\<Component name="App">
        \\  <Router>
        \\    <Page path="/" component="HomePage" />
        \\    <Page path="/about" component="AboutPage" />
        \\  </Router>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@const sax_App_route_path_0 = utf8:\"/\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@const sax_App_route_component_0 = utf8:\"HomePage\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@export sax_app_router_init(path: ptr):"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_router_init"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_router_init(*"));
}

test "lowerer emits ffi wrapper bridge for handlers" {
    const source =
        \\<Component name="Bridge">
        \\  <div></div>
        \\  @ffi_wrapper call_dom:
        \\  L_ENTRY:
        \\    raw = *state
        \\    return raw
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@ffi_wrapper sax_bridge_call_dom_ffi(ctx: ptr):"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@export sax_bridge_call_dom(ctx: ptr):"));
}

test "lowerer emits user component composition calls" {
    const source =
        \\<Component name="App">
        \\  <Layout title="Home">
        \\    Lead
        \\    <span>Hi</span>
        \\    Tail
        \\  </Layout>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "node_0 = call @sax_layout_mount(host)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "slot_0 = call @sax_layout_slot(node_0)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_create_text("));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_append_child(slot_0, node_1)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 3, "call @sax_dom_append_child(slot_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_layout_render(node_0)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_layout_destroy(node_0)"));
}

test "lowerer emits shared declarations only for the first composed component" {
    const source =
        \\<Component name="App">
        \\  <Badge />
        \\</Component>
        \\<Component name="Badge">
        \\  <span>Badge</span>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    for (program.components, 0..) |component, idx| {
        var component_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, component);
        defer component_lowerer.deinit();
        try component_lowerer.lower(&out, .{ .emit_shared_decls = idx == 0 });
    }

    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, out.items, "@import \"sa_std/vec.sa\""));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, out.items, "@export sax_array_push"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, out.items, "@extern sax_dom_create("));
}

test "lowerer emits slot projection exports for child components" {
    const source =
        \\<Component name="Layout">
        \\  <section class="layout">
        \\    <header>Header</header>
        \\    <Slot />
        \\  </section>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@export sax_layout_mount(parent_h: i64) -> ptr:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@export sax_layout_slot(ctx: ptr) -> i64:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "slot_h = load dom+sax_Layout_node_Slot as i64"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "slot_h = load dom+sax_Layout_node_Slot as ptr") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"slot\""));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"Slot\"") == null);
}

test "lowerer forwards user component event props to component roots" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\  <Action onClick={inc} onChange={changed}>Projected</Action>
        \\  @inc:
        \\  L_ENTRY:
        \\    count = load state+App_count as i64
        \\    count = add count, 1
        \\    store state+App_count, count as i64
        \\    call @render()
        \\    ret
        \\  @changed:
        \\  L_ENTRY:
        \\    store state+App_count, 7 as i64
        \\    call @render()
        \\    ret
        \\  !count
        \\</Component>
        \\<Component name="Action">
        \\  <button class="action"><Slot /></button>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    for (program.components, 0..) |component, idx| {
        var component_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, component);
        defer component_lowerer.deinit();
        try component_lowerer.lower(&out, .{ .emit_shared_decls = idx == 0 });
    }

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@export sax_action_root(ctx: ptr) -> i64:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "root_h = load dom+sax_Action_node_button as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "node_0_root = call @sax_action_root(node_0)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 3, "call @sax_dom_bind_event(node_0_root,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"click\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"input\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"change\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"sax_app_inc\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"sax_app_changed\""));
}

test "lowerer normalizes user component onChange from internal form controls" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\  <CheckAction onChange={changed} />
        \\  <TextAction onChange={changed} />
        \\  @changed:
        \\  L_ENTRY:
        \\    count = load state+App_count as i64
        \\    count = add count, 1
        \\    store state+App_count, count as i64
        \\    call @render()
        \\    ret
        \\  !count
        \\</Component>
        \\<Component name="CheckAction">
        \\  <span><input type="checkbox" /></span>
        \\</Component>
        \\<Component name="TextAction">
        \\  <span><input type="text" /></span>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    for (program.components, 0..) |component, idx| {
        var component_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, component);
        defer component_lowerer.deinit();
        try component_lowerer.lower(&out, .{ .emit_shared_decls = idx == 0 });
    }

    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, out.items, "call @sax_dom_bind_event("));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"change\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"input\""));
}

test "lowerer projects slot context props before explicit child props" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    explicit = 0 as i1
        \\  </state>
        \\  <Provider dense>
        \\    <Child>Inherited</Child>
        \\    <Child dense={explicit}>Explicit</Child>
        \\  </Provider>
        \\  !explicit
        \\</Component>
        \\<Component name="Provider">
        \\  <state>
        \\    dense = 0 as i1
        \\  </state>
        \\  <section><Slot contextProps="dense" /></section>
        \\  !dense
        \\</Component>
        \\<Component name="Child">
        \\  <state>
        \\    dense = 0 as i1
        \\  </state>
        \\  <p className="{dense ? 'dense' : ''}"><Slot /></p>
        \\  !dense
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    for (program.components, 0..) |component, idx| {
        var component_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, component);
        defer component_lowerer.deinit();
        try component_lowerer.lower(&out, .{ .emit_shared_decls = idx == 0 });
    }

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "Child_ctx_0_state = load node_0+0 as ptr"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Child_ctx_0_state = load node_0+Provider_CTX_state as ptr") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "Child_ctx_0_raw = load Child_ctx_0_state+0 as i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_child_set_dense(node_1, Child_ctx_0_wide)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "!context_child_"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Child_1_ctx_0_raw") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_child_set_dense(node_2,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"contextProps\"") == null);
}

test "lowerer carries slot context props through transparent user components" {
    const source =
        \\<Component name="App">
        \\  <Provider tone="secondary">
        \\    <Wrapper>
        \\      <Child>Inherited</Child>
        \\    </Wrapper>
        \\  </Provider>
        \\</Component>
        \\<Component name="Provider">
        \\  <state>
        \\    tone = 'primary' as ptr
        \\    tone_len = 7
        \\  </state>
        \\  <section><Slot contextProps="tone" contextScope="descendants" /></section>
        \\  !tone !tone_len
        \\</Component>
        \\<Component name="Wrapper">
        \\  <div><Slot /></div>
        \\</Component>
        \\<Component name="Child">
        \\  <state>
        \\    tone = 'default' as ptr
        \\    tone_len = 7
        \\  </state>
        \\  <p className="{tone == 'secondary' ? 'secondary' : ''}"><Slot /></p>
        \\  !tone !tone_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    for (program.components, 0..) |component, idx| {
        var component_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, component);
        defer component_lowerer.deinit();
        try component_lowerer.lower(&out, .{ .emit_shared_decls = idx == 0 });
    }

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "Child_ctx_0_state = load node_0+0 as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_child_set_tone_str(node_2, *Child_ctx_0_ptr, Child_ctx_0_len)"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_child_set_tone(node_2, *sax_App_") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"contextProps\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"contextScope\"") == null);
}

test "lowerer treats provider-wrapped slots as context sources" {
    const source =
        \\<Component name="App">
        \\  <Wrapper tone="secondary">
        \\    <Child>Inherited</Child>
        \\  </Wrapper>
        \\</Component>
        \\<Component name="Wrapper">
        \\  <state>
        \\    tone = 'primary' as ptr
        \\    tone_len = 7
        \\  </state>
        \\  <Provider tone={tone}>
        \\    <Slot />
        \\  </Provider>
        \\  !tone !tone_len
        \\</Component>
        \\<Component name="Provider">
        \\  <state>
        \\    tone = 'primary' as ptr
        \\    tone_len = 7
        \\  </state>
        \\  <section><Slot contextProps="tone" contextScope="descendants" /></section>
        \\  !tone !tone_len
        \\</Component>
        \\<Component name="Child">
        \\  <state>
        \\    tone = 'default' as ptr
        \\    tone_len = 7
        \\  </state>
        \\  <p className="{tone == 'secondary' ? 'secondary' : ''}"><Slot /></p>
        \\  !tone !tone_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    for (program.components, 0..) |component, idx| {
        var component_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, component);
        defer component_lowerer.deinit();
        try component_lowerer.lower(&out, .{ .emit_shared_decls = idx == 0 });
    }

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "Child_ctx_0_state = load node_0+0 as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_child_set_tone_str(node_1, *Child_ctx_0_ptr, Child_ctx_0_len)"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_child_set_tone(node_1, *sax_App_") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"contextProps\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"contextScope\"") == null);
}

test "lowerer keeps slot context props direct by default" {
    const source =
        \\<Component name="App">
        \\  <Provider tone="secondary">
        \\    <Wrapper>
        \\      <Child>Default direct scope</Child>
        \\    </Wrapper>
        \\  </Provider>
        \\</Component>
        \\<Component name="Provider">
        \\  <state>
        \\    tone = 'primary' as ptr
        \\    tone_len = 7
        \\  </state>
        \\  <section><Slot contextProps="tone" /></section>
        \\  !tone !tone_len
        \\</Component>
        \\<Component name="Wrapper">
        \\  <div><Slot /></div>
        \\</Component>
        \\<Component name="Child">
        \\  <state>
        \\    tone = 'default' as ptr
        \\    tone_len = 7
        \\  </state>
        \\  <p className="{tone == 'secondary' ? 'secondary' : ''}"><Slot /></p>
        \\  !tone !tone_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    for (program.components, 0..) |component, idx| {
        var component_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, component);
        defer component_lowerer.deinit();
        try component_lowerer.lower(&out, .{ .emit_shared_decls = idx == 0 });
    }

    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_child_set_tone_str(node_2") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"contextProps\"") == null);
}

test "lowerer refreshes direct projected text children for user components" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\  <Layout>Projected {count}</Layout>
        \\  @inc:
        \\  L_ENTRY:
        \\    count = load state+App_count as i64
        \\    count = add count, 1
        \\    store state+App_count, count as i64
        \\    call @render()
        \\    ret
        \\  !count
        \\</Component>
        \\<Component name="Layout">
        \\  <section><Slot /></section>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "#def sax_App_node_Layout_text_0 = +8"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "#def sax_App_node_Layout_text_1 = +16"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "store dom+sax_App_node_Layout_text_0, text_child_0_0 as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "store dom+sax_App_node_Layout_text_1, text_child_0_1 as i64"));

    const inc_start = std.mem.indexOf(u8, out.items, "@ffi_wrapper sax_app_inc_ffi(ctx: ptr):") orelse return error.TestUnexpectedResult;
    const inc_end = std.mem.indexOf(u8, out.items[inc_start..], "@export sax_app_destroy(ctx: ptr):") orelse out.items.len - inc_start;
    const inc_block = out.items[inc_start .. inc_start + inc_end];
    try std.testing.expect(std.mem.containsAtLeast(u8, inc_block, 1, "projected_text_render_0_1 = load dom+sax_App_node_Layout_text_1 as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, inc_block, 1, "call @sax_dom_set_text(projected_text_render_0_1,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, inc_block, 1, "!node_0"));
}

test "lowerer removes slotted text-node handles during destroy" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\  <section>Prefix {count}<span>child</span></section>
        \\  <Layout>Projected {count}</Layout>
        \\  !count
        \\</Component>
        \\<Component name="Layout">
        \\  <section><Slot /></section>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    const destroy_start = std.mem.indexOf(u8, out.items, "@ffi_wrapper sax_app_destroy_ffi(ctx: ptr):") orelse return error.TestUnexpectedResult;
    const destroy_end = std.mem.indexOf(u8, out.items[destroy_start..], "@const sax_App_") orelse out.items.len - destroy_start;
    const destroy_block = out.items[destroy_start .. destroy_start + destroy_end];
    try std.testing.expect(std.mem.containsAtLeast(u8, destroy_block, 1, "text_node_destroy_0_0 = load dom+sax_App_node_section_text_0 as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, destroy_block, 1, "call @sax_dom_remove_self(text_node_destroy_0_0)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, destroy_block, 1, "text_node_destroy_2_0 = load dom+sax_App_node_Layout_text_0 as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, destroy_block, 1, "text_node_destroy_2_1 = load dom+sax_App_node_Layout_text_1 as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, destroy_block, 1, "!node_0"));
    try std.testing.expect(std.mem.containsAtLeast(u8, destroy_block, 1, "!node_2"));
    const projected_text_remove_pos = std.mem.indexOf(u8, destroy_block, "call @sax_dom_remove_self(text_node_destroy_2_1)") orelse return error.TestUnexpectedResult;
    const child_destroy_pos = std.mem.indexOf(u8, destroy_block, "call @sax_layout_destroy(node_2)") orelse return error.TestUnexpectedResult;
    try std.testing.expect(projected_text_remove_pos < child_destroy_pos);
}

test "lowerer emits numeric prop setter calls for user components" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 4
        \\    active = 0 as i1
        \\  </state>
        \\  <Badge count="{count + 1}" active="1" title="Ignored string" />
        \\  !count
        \\</Component>
        \\<Component name="Badge">
        \\  <state>
        \\    count = 0
        \\    active = 0 as i1
        \\  </state>
        \\  <span>{count}</span>
        \\  !count !active
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "node_0 = call @sax_badge_mount(host)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_badge_set_count(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_badge_set_active(node_0, 1)"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "sax_badge_set_title") == null);
}

test "lowerer emits ternary string prop setter calls for user components" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    visible = 0 as i1
        \\  </state>
        \\  <Field type={visible ? 'text' : 'password'} />
        \\  @toggle:
        \\  L_ENTRY:
        \\    store state+App_visible, 1 as i1
        \\    call @render()
        \\    ret
        \\  !visible
        \\</Component>
        \\<Component name="Field">
        \\  <state>
        \\    type = 'text' as ptr
        \\    type_len = 4
        \\  </state>
        \\  <input type={type} />
        \\  !type !type_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_field_set_type_str(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "prop_str_ternary"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = stack_alloc 8"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"password\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"text\""));
}

test "lowerer maps normalized React prop aliases into user component state" {
    const source =
        \\<Component name="App">
        \\  <Field readOnly autoFocus className="dense" aria-label="Name" aria-labelledby="field-title" aria-describedby="field-helper" />
        \\</Component>
        \\<Component name="Field">
        \\  <state>
        \\    readOnly = 0 as i1
        \\    autoFocus = 0 as i1
        \\    className = alloc 32
        \\    className_len = 0
        \\    ariaLabel = alloc 64
        \\    ariaLabel_len = 0
        \\    ariaLabelledby = alloc 64
        \\    ariaLabelledby_len = 0
        \\    ariaDescribedby = alloc 64
        \\    ariaDescribedby_len = 0
        \\  </state>
        \\  <input readonly={readOnly} className="{className}" aria-label="{ariaLabel}" aria-labelledby="{ariaLabelledby}" aria-describedby="{ariaDescribedby}" />
        \\  !readOnly !autoFocus !className !className_len !ariaLabel !ariaLabel_len !ariaLabelledby !ariaLabelledby_len !ariaDescribedby !ariaDescribedby_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_field_set_readOnly(node_0, 1)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_field_set_autoFocus(node_0, 1)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_field_set_className_str(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_field_set_ariaLabel_str(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_field_set_ariaLabelledby_str(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_field_set_ariaDescribedby_str(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "sax_field_set_readonly") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "sax_field_set_autofocus") == null);
}

test "lowerer maps normalized SVG camelCase prop aliases into user component state" {
    const source =
        \\<Component name="App">
        \\  <Glyph fontSize="large" />
        \\</Component>
        \\<Component name="Glyph">
        \\  <state>
        \\    fontSize = 'medium' as ptr
        \\    fontSize_len = 6
        \\  </state>
        \\  <svg className="{fontSize}" />
        \\  !fontSize !fontSize_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_glyph_set_fontSize_str(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "sax_glyph_set_font-size") == null);
}

test "lowerer emits state setter exports for numeric child props" {
    const source =
        \\<Component name="Badge">
        \\  <state>
        \\    count = 0
        \\    active = 0 as i1
        \\  </state>
        \\  <span>{count}</span>
        \\  !count !active
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@export sax_badge_set_count(ctx: ptr, value: i64):"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "store state+Badge_count, value as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@export sax_badge_set_active(ctx: ptr, value: i64):"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "is_set = ne value, 0"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_badge_render(ctx)"));
}

test "lowerer emits string prop setters for ptr state" {
    const source =
        \\<Component name="App">
        \\  <Label title="Hello string prop" />
        \\</Component>
        \\<Component name="Label">
        \\  <state>
        \\    title = alloc 64
        \\    title_len = 0
        \\  </state>
        \\  <p>{title}</p>
        \\  !title !title_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var app_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer app_lowerer.deinit();

    var app_out = std.ArrayList(u8).init(std.testing.allocator);
    defer app_out.deinit();
    try app_lowerer.lower(&app_out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "call @sax_label_set_title_str(node_0, *sax_App_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"Hello string prop\""));

    var label_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[1]);
    defer label_lowerer.deinit();

    var label_out = std.ArrayList(u8).init(std.testing.allocator);
    defer label_out.deinit();
    try label_lowerer.lower(&label_out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, label_out.items, 1, "@export sax_label_set_title_str(ctx: ptr, src: ptr, len: i64):"));
    try std.testing.expect(std.mem.containsAtLeast(u8, label_out.items, 1, "dst = load state+Label_title as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, label_out.items, 1, "call @sax_mem_copy(*dst, *src, len)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, label_out.items, 1, "store state+Label_title_len, len as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, label_out.items, 1, "_ptr = load state+Label_title as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, label_out.items, 1, "_len = load state+Label_title_len as i64"));
}

test "lowerer passes static object props into child ptr state" {
    const source =
        \\<Component name="App">
        \\  <Widget config={{ title: "Object Prop", count: 3, active: true, tags: ["alpha", "beta"], nested: { size: 2 } }} />
        \\</Component>
        \\<Component name="Widget">
        \\  <state>
        \\    config = alloc 256
        \\    config_len = 0
        \\  </state>
        \\  <pre>{config}</pre>
        \\  !config !config_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var app_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer app_lowerer.deinit();

    var app_out = std.ArrayList(u8).init(std.testing.allocator);
    defer app_out.deinit();
    try app_lowerer.lower(&app_out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "@extern sax_json_normalize_object(*src_ptr: ptr, src_len: i64, *dst_ptr: ptr, dst_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "call @sax_json_normalize_object(*sax_App_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "call @sax_widget_set_config_str(node_0, *prop_obj_Widget_0_normalized_buf, prop_obj_Widget_0_normalized_len)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"title\\\":\\\"Object Prop\\\",\\\"count\\\":3,\\\"active\\\":true,\\\"tags\\\":[\\\"alpha\\\",\\\"beta\\\"],\\\"nested\\\":{\\\"size\\\":2}}\""));

    var widget_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[1]);
    defer widget_lowerer.deinit();

    var widget_out = std.ArrayList(u8).init(std.testing.allocator);
    defer widget_out.deinit();
    try widget_lowerer.lower(&widget_out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, widget_out.items, 1, "@export sax_widget_set_config_str(ctx: ptr, src: ptr, len: i64):"));
    try std.testing.expect(std.mem.containsAtLeast(u8, widget_out.items, 1, "store state+Widget_config_len, len as i64"));
}

test "lowerer projects MUI classes and slotProps className objects into slot states" {
    const source =
        \\<Component name="App">
        \\  <Menu classes={{ root: "menu-root-class", paper: "menu-paper-class", list: "menu-list-class" }} slotProps={{ root: { className: "menu-root-slot" }, paper: { className: "menu-paper-slot" }, list: { className: "menu-list-slot" } }}>
        \\    <MenuItem>Action</MenuItem>
        \\  </Menu>
        \\</Component>
        \\<Component name="Menu">
        \\  <state>
        \\    classesRoot = alloc 128
        \\    classesRoot_len = 0
        \\    classesPaper = alloc 128
        \\    classesPaper_len = 0
        \\    classesList = alloc 128
        \\    classesList_len = 0
        \\    slotPropsRootClassName = alloc 128
        \\    slotPropsRootClassName_len = 0
        \\    slotPropsPaperClassName = alloc 128
        \\    slotPropsPaperClassName_len = 0
        \\    slotPropsListClassName = alloc 128
        \\    slotPropsListClassName_len = 0
        \\  </state>
        \\  <div className="MuiMenu-root {classesRoot} {slotPropsRootClassName}">
        \\    <div className="MuiMenu-paper {classesPaper} {slotPropsPaperClassName}">
        \\      <ul className="MuiMenu-list {classesList} {slotPropsListClassName}">
        \\        <Slot />
        \\      </ul>
        \\    </div>
        \\  </div>
        \\  !classesRoot !classesRoot_len !classesPaper !classesPaper_len !classesList !classesList_len !slotPropsRootClassName !slotPropsRootClassName_len !slotPropsPaperClassName !slotPropsPaperClassName_len !slotPropsListClassName !slotPropsListClassName_len
        \\</Component>
        \\<Component name="MenuItem">
        \\  <li className="MuiMenuItem-root"><Slot /></li>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var app_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer app_lowerer.deinit();

    var app_out = std.ArrayList(u8).init(std.testing.allocator);
    defer app_out.deinit();
    try app_lowerer.lower(&app_out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "call @sax_menu_set_classesRoot_str(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "call @sax_menu_set_classesPaper_str(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "call @sax_menu_set_classesList_str(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "call @sax_menu_set_slotPropsRootClassName_str(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "call @sax_menu_set_slotPropsPaperClassName_str(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "call @sax_menu_set_slotPropsListClassName_str(node_0,"));
}

test "lowerer passes dynamic numeric object props into child ptr state" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 4
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
        \\    branch = alloc 64
        \\    branch_len = 0
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ ...extra, ["title"]: title, [title]: count, [count + 1]: active, [active]: count, [active ? active : fallback_active]: idle_score, [active ? fallback_active : true]: count, [active ? fallback : null]: count, [active ? small_score : fallback_small_score]: active, [active ? small_score : 4]: active, [active ? ratio : fallback_ratio]: count, [active ? ratio : 0.25]: count, [((count + 2) * 3) - 1]: active, [active ? "enabled" : "disabled"]: count, [active ? title : fallback]: count, [active ? "ready" : fallback]: count, [active ? count : idle_score]: active, [active ? count : 0]: count, ...(active ? branch : { fallback_branch: true }), ...(active ? { active_null_branch: true } : null), ...(active ? nested_extra : null), ...(active ? nested_extra : branch), ...(active && { active_and_branch: true }), ...(!active && { idle_and_branch: true }), ...(active && branch), ...(!active && branch), ...(active || { idle_or_branch: true }), ...(!active || { active_or_branch: true }), ...(active || nested_extra), ...(!active || nested_extra), status: active ? title : fallback, label: active ? "ready" : fallback, nullable: active ? title : null, score: active ? count : idle_score, bonus: active ? count : 0, rating: active ? small_score : fallback_small_score, rating_floor: active ? small_score : 4, visible: active ? active : fallback_active, pinned: active ? true : fallback_active, precision: active ? ratio : fallback_ratio, precision_floor: active ? ratio : 0.25, ...{ [active ? "spread_ready" : "spread_idle"]: count, [count + 100]: active, [active]: count, spread: "static", spread_count: count }, count: count, active: active, computed_items: [{ size: 1, [active ? "item_ready" : "item_idle"]: count, [active ? count : idle_score]: active, [active ? title : fallback]: count, current: count }], leading_computed_items: [{ [active ? "leading_item_ready" : "leading_item_idle"]: count, [active ? count : idle_score]: active, [active ? title : fallback]: count, current: count }], items: [{ size: 1, ...nested_extra, ["current"]: count, ...(!active && { idle_item: true }), ...(active && { active_item: true }), ...(active ? { active_item_branch: true } : null), ...(active || { idle_item_or: true }), ...(!active || { active_item_or: true }), ...(active || branch), ...(!active || branch), ...{ [active ? "nested_spread_ready" : "nested_spread_idle"]: count, [count + 200]: active, [active]: count, enabled: true, spread_active: active } }], and_ptr_items: [{ size: 1, ...(active && branch), ...(!active && branch), current: count }], leading_items: [{ ...nested_extra, ["current"]: count, ...{ enabled: true, spread_active: active } }], leading_static_spread_items: [{ ...{ [active ? "leading_spread_ready" : "leading_spread_idle"]: count, [count + 300]: active, [active]: count, enabled: true, spread_active: active }, current: count }], leading_conditional_items: [{ ...(!active && { idle_leading_item: true }), current: count }], leading_active_items: [{ ...(active && { active_leading_item: true }), current: count }], leading_ptr_and_items: [{ ...(active && nested_extra), current: count }], leading_negated_ptr_and_items: [{ ...(!active && nested_extra), current: count }], leading_null_items: [{ ...(active ? { active_leading_branch: true } : null), current: count }], leading_ptr_null_items: [{ ...(active ? nested_extra : null), current: count }], leading_ptr_fallback_items: [{ ...(active ? nested_extra : { idle_ptr_fallback: true }), current: count }], leading_ptr_branch_items: [{ ...(active ? nested_extra : branch), current: count }], leading_or_items: [{ ...(active || { idle_leading_or: true }), current: count }], leading_ptr_or_items: [{ ...(active || nested_extra), current: count }], leading_negated_or_items: [{ ...(!active || { active_leading_or: true }), current: count }], leading_negated_ptr_or_items: [{ ...(!active || nested_extra), current: count }], leading_static_spread_nested: { ...{ [active ? "leading_nested_spread_ready" : "leading_nested_spread_idle"]: count, [count + 400]: active, [active]: count, enabled: true, spread_active: active }, current: count }, ternary_static_spread_items: [{ ...{ [active ? active : fallback_active]: idle_score, [active ? fallback_active : true]: count, [active ? false : true]: count, current: count } }], leading_nested: { [active ? "leading_nested_ready" : "leading_nested_idle"]: count, [active ? count : idle_score]: active, [active ? title : fallback]: count, current: count }, nested: { ...(active ? nested_extra : { idle_nested_branch: true }), ...(active ? nested_extra : branch), ...(active ? nested_extra : null), ...nested_extra, ...(active ? { active_nested_branch: true } : null), ...(active && { active_nested_and: true }), ...(!active && { idle_nested_and: true }), ...(active || { idle_nested_or: true }), ...(!active || { active_nested_or: true }), ...(active && branch), ...(!active && branch), ...(active || branch), ...(!active || branch), [active ? "nested_ready" : "nested_idle"]: count, [active ? count : idle_score]: active, [active ? title : fallback]: count, ["current"]: count, ...{ [active ? "nested_spread_ready" : "nested_spread_idle"]: count, [count + 200]: active, [active]: count, enabled: true, spread_active: active } } }} />
        \\  !count !idle_score !small_score !fallback_small_score !ratio !fallback_ratio !active !fallback_active !title !title_len !fallback !fallback_len !extra !extra_len !branch !branch_len !nested_extra !nested_extra_len
        \\</Component>
        \\<Component name="Widget">
        \\  <state>
        \\    config = alloc 256
        \\    config_len = 0
        \\  </state>
        \\  <pre>{config}</pre>
        \\  !config !config_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var app_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer app_lowerer.deinit();

    var app_out = std.ArrayList(u8).init(std.testing.allocator);
    defer app_out.deinit();
    try app_lowerer.lower(&app_out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "prop_tpl_Widget_0_buf = stack_alloc"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "load state+App_title as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "load state+App_title_len as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "@extern sax_json_write_string(*src_ptr: ptr, src_len: i64, *dst_ptr: ptr, dst_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "@extern sax_json_normalize_object(*src_ptr: ptr, src_len: i64, *dst_ptr: ptr, dst_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 17, "load state+App_nested_extra as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 17, "load state+App_nested_extra_len as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 14, "load state+App_branch as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 14, "load state+App_branch_len as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 2, "call @sax_json_write_string(*prop_tpl_Widget_0_json_str_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_key_expr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_key_open_dst"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, " = mul "));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, " = sub "));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "KEY_MIXED_TERNARY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"\\\"enabled\\\"\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"\\\"disabled\\\"\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "KEY_MIXED_TERNARY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_key_mixed_ternary_written"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"\\\"null\\\"\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "KEY_I64_TERNARY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_key_i64_ternary_written"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_key_i64_ternary_false_value_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "KEY_I32_TERNARY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_key_i32_ternary_written"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_key_i32_ternary_false_raw_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "KEY_I1_TERNARY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_key_i1_ternary_true"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_key_i1_ternary_false_value_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "KEY_F64_TERNARY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_key_f64_ternary_written"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_key_f64_ternary_false_value_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "call @sax_ftoa_bits("));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "OBJ_TERNARY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_obj_ternary_written"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"fallback_branch\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"active_null_branch\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"active_and_branch\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"idle_and_branch\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"idle_item\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"idle_leading_item\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"idle_ptr_fallback\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"idle_nested_branch\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"active_nested_branch\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"active_nested_and\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"idle_nested_and\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"idle_nested_or\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"active_nested_or\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"active_leading_item\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"active_leading_branch\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"idle_leading_or\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"active_leading_or\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"active_item\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"active_item_branch\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"idle_item_or\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"active_item_or\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"idle_or_branch\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{\\\"active_or_branch\\\":true}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"{}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "VALUE_TERNARY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_value_ternary_written"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"\\\"ready\\\"\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"null\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "I64_TERNARY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_i64_ternary_written"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_i64_ternary_false_value_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "I32_TERNARY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_i32_ternary_written"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_i32_ternary_false_raw_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "F64_TERNARY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_f64_ternary_written"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_f64_ternary_false_value_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "I1_TERNARY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_i1_ternary_true"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, " = 1 as i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "KEY_BOOL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "@extern sax_json_write_object_members(*src_ptr: ptr, src_len: i64, *dst_ptr: ptr, dst_len: i64, prefix_comma: i1) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "call @sax_json_write_object_members(*prop_tpl_Widget_0_json_obj_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "JSON_COMMA"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "json_obj_has_members"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 4, "load state+App_count as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "load state+App_active as i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 2, "call @sax_itoa("));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "BOOL_TRUE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "BOOL_FALSE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"true\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"false\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "call @sax_json_normalize_object(*prop_tpl_Widget_0_buf, prop_tpl_Widget_0_len"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "call @sax_widget_set_config_str(node_0, *prop_tpl_Widget_0_normalized_buf, prop_tpl_Widget_0_normalized_len)"));
}

test "lowerer emits dynamic array values inside child object props" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 4
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
        \\  <Widget config={{ tags: ["alpha", title, count, active, active ? title : fallback, active ? count : idle_score, active ? count : 0, active ? small_score : fallback_small_score, active ? small_score : 4, active ? active : fallback_active, active ? false : true, active ? null : fallback, active ? ratio : fallback_ratio, active ? ratio : 0.25, active ? "ready" : fallback] }} />
        \\  !count !idle_score !small_score !fallback_small_score !ratio !fallback_ratio !active !fallback_active !title !title_len !fallback !fallback_len
        \\</Component>
        \\<Component name="Widget">
        \\  <state>
        \\    config = alloc 128
        \\    config_len = 0
        \\  </state>
        \\  <pre>{config}</pre>
        \\  !config !config_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var app_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer app_lowerer.deinit();

    var app_out = std.ArrayList(u8).init(std.testing.allocator);
    defer app_out.deinit();
    try app_lowerer.lower(&app_out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "prop_tpl_Widget_0_buf = stack_alloc"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "call @sax_json_write_string(*prop_tpl_Widget_0_json_str_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "load state+App_count as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "load state+App_active as i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "call @sax_itoa("));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "VALUE_TERNARY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "utf8:\"\\\"ready\\\"\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "I64_TERNARY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "I32_TERNARY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "F64_TERNARY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "I1_TERNARY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, " = 1 as i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, " = 0 as i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "BOOL_TRUE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "BOOL_FALSE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "call @sax_json_normalize_object(*prop_tpl_Widget_0_buf, prop_tpl_Widget_0_len"));
    try std.testing.expect(std.mem.containsAtLeast(u8, app_out.items, 1, "call @sax_widget_set_config_str(node_0, *prop_tpl_Widget_0_normalized_buf, prop_tpl_Widget_0_normalized_len)"));
}

test "lowerer passes parent ptr state into child string props" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    title = alloc 64
        \\    title_len = 0
        \\  </state>
        \\  <Label title="{title}" />
        \\  !title !title_len
        \\</Component>
        \\<Component name="Label">
        \\  <state>
        \\    title = alloc 64
        \\    title_len = 0
        \\  </state>
        \\  <p>{title}</p>
        \\  !title !title_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var app_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer app_lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try app_lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "prop_str_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "_ptr = load state+App_title as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "_len = load state+App_title_len as i64"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_json_write_string") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_label_set_title_str(node_0, *prop_str_"));
}

test "lowerer emits ptr state string slices for DOM attrs" {
    const source =
        \\<Component name="ImageCard">
        \\  <state>
        \\    label = alloc 32
        \\    label_len = 0
        \\  </state>
        \\  <img alt="{label}" title="{label}" />
        \\  !label !label_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "_ptr = load state+ImageCard_label as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "_len = load state+ImageCard_label_len as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"alt\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"title\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_attr(node_0,") == null);
}

test "lowerer emits template buffers for DOM attrs and child string props" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    label = alloc 32
        \\    label_len = 0
        \\    count = 7
        \\  </state>
        \\  <img alt="Label: {label} #{count}" />
        \\  <Label title="Child {label} #{count}" />
        \\  !label !label_len !count
        \\</Component>
        \\<Component name="Label">
        \\  <state>
        \\    title = alloc 64
        \\    title_len = 0
        \\  </state>
        \\  <p>{title}</p>
        \\  !title !title_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var app_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer app_lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try app_lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "attr_tpl_node_0_alt_buf = stack_alloc"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "prop_tpl_Label_0_buf = stack_alloc"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "_ptr = load state+App_label as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "_len = load state+App_label_len as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, " = load state+App_count as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_itoa("));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_label_set_title_str(node_1, *prop_tpl_Label_0_buf, prop_tpl_Label_0_len)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"Label: \""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"Child \""));
}

test "lowerer emits static string ternary pieces inside DOM attr templates" {
    const source =
        \\<Component name="ClassLab">
        \\  <state>
        \\    disabled = 0 as i1
        \\  </state>
        \\  <button className="MuiButton-root{disabled ? ' Mui-disabled MuiButton-disabled' : ''}">Save</button>
        \\  !disabled
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "attr_tpl_node_0_class_buf = stack_alloc"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = load state+ClassLab_disabled as i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "_TERNARY_TRUE_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "jmp L_attr_tpl_node_0_class_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "_TERNARY_DONE_1"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "br ->") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\" Mui-disabled MuiButton-disabled\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"MuiButton-root\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_str_prop(node_0,"));
}

test "lowerer emits static string ternary for whole DOM attr interpolation" {
    const source =
        \\<Component name="AriaLab">
        \\  <state>
        \\    open = 0 as i1
        \\  </state>
        \\  <div aria-hidden="{open ? 'false' : 'true'}">Overlay</div>
        \\  !open
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "attr_ternary_buf_node_0_aria-hidden = stack_alloc"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = load state+AriaLab_open as i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"aria-hidden\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"false\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"true\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_attr(node_0,"));
}

test "lowerer emits truthy and-and ternary pieces inside DOM attr templates" {
    const source =
        \\<Component name="ClassLab">
        \\  <state>
        \\    primary_len = 0
        \\    secondary_len = 0
        \\  </state>
        \\  <div className="MuiListItemText-root{primary_len && secondary_len ? ' MuiListItemText-multiline' : ''}">Body</div>
        \\  !primary_len !secondary_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "load state+ClassLab_primary_len as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "load state+ClassLab_secondary_len as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, " = ne "));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = and "));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\" MuiListItemText-multiline\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_str_prop(node_0,"));
}

test "lowerer emits ptr equality ternary pieces inside DOM attr templates" {
    const source =
        \\<Component name="ClassLab">
        \\  <state>
        \\    position = alloc 32
        \\    position_len = 3
        \\  </state>
        \\  <div className="MuiMobileStepper-root{position == 'top' ? ' MuiMobileStepper-positionTop' : ''}{position == 'bottom' ? ' MuiMobileStepper-positionBottom' : ''}">Body</div>
        \\  !position !position_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "load state+ClassLab_position as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "load state+ClassLab_position_len as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_mem_eq("));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"top\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"bottom\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\" MuiMobileStepper-positionTop\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\" MuiMobileStepper-positionBottom\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_str_prop(node_0,"));
}

test "lowerer emits ptr-equality and-and ternary pieces inside DOM attr templates" {
    const source =
        \\<Component name="ClassLab">
        \\  <state>
        \\    vertical = alloc 32
        \\    vertical_len = 6
        \\    horizontal = alloc 32
        \\    horizontal_len = 5
        \\  </state>
        \\  <div className="MuiSnackbar-root{vertical == 'top' && horizontal == 'right' ? ' MuiSnackbar-anchorOriginTopRight' : ''}">Body</div>
        \\  !vertical !vertical_len !horizontal !horizontal_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "load state+ClassLab_vertical as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "load state+ClassLab_horizontal as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 3, " = and "));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\" MuiSnackbar-anchorOriginTopRight\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_str_prop(node_0,"));
}

test "lowerer emits chained ptr-equality ternary pieces inside DOM attr templates" {
    const source =
        \\<Component name="ClassLab">
        \\  <state>
        \\    vertical = alloc 32
        \\    vertical_len = 6
        \\    horizontal = alloc 32
        \\    horizontal_len = 5
        \\    overlap = alloc 32
        \\    overlap_len = 11
        \\  </state>
        \\  <div className="MuiBadge-badge{vertical == 'top' && horizontal == 'right' && overlap == 'rectangular' ? ' MuiBadge-anchorOriginTopRightRectangular' : ''}">Body</div>
        \\  !vertical !vertical_len !horizontal !horizontal_len !overlap !overlap_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "load state+ClassLab_vertical as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "load state+ClassLab_horizontal as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "load state+ClassLab_overlap as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 3, "call @sax_mem_eq("));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 5, " = and "));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\" MuiBadge-anchorOriginTopRightRectangular\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_str_prop(node_0,"));
}

test "lowerer emits mixed ptr-and-int equality ternary pieces inside DOM attr templates" {
    const source =
        \\<Component name="ClassLab">
        \\  <state>
        \\    variant = alloc 32
        \\    variant_len = 9
        \\    elevation = 1
        \\  </state>
        \\  <div className="MuiPaper-root{variant == 'elevation' && elevation == 3 ? ' MuiPaper-elevation3' : ''}">Body</div>
        \\  !variant !variant_len !elevation
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "load state+ClassLab_variant as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "load state+ClassLab_elevation as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_mem_eq("));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, " = and "));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\" MuiPaper-elevation3\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_str_prop(node_0,"));
}

test "lowerer accepts Grid ownerState class templates" {
    const source =
        \\<Component name="GridSmoke">
        \\  <section className="mui-grid-smoke">
        \\    <Grid container spacing={2} direction="row-reverse" wrap="wrap-reverse" className="mui-grid-owner-state">
        \\      <Grid size={6}>Grid half item</Grid>
        \\      <Grid size={12}>Grid full item</Grid>
        \\    </Grid>
        \\  </section>
        \\</Component>
        \\
        \\<Component name="Grid">
        \\  <state>
        \\    className = alloc 256
        \\    className_len = 0
        \\    columns = 12
        \\    columnSpacing = 0
        \\    container = 0 as i1
        \\    direction = 'row' as ptr
        \\    direction_len = 3
        \\    offset = 0
        \\    rowSpacing = 0
        \\    size = 0
        \\    spacing = 0
        \\    wrap = 'wrap' as ptr
        \\    wrap_len = 4
        \\  </state>
        \\  <div className="MuiGrid-root{container ? ' MuiGrid-container' : ''}{wrap == 'nowrap' ? ' MuiGrid-wrap-xs-nowrap' : ''}{wrap == 'wrap-reverse' ? ' MuiGrid-wrap-xs-wrap-reverse' : ''}{direction == 'row' ? ' MuiGrid-direction-xs-row' : ''}{direction == 'row-reverse' ? ' MuiGrid-direction-xs-row-reverse' : ''}{direction == 'column' ? ' MuiGrid-direction-xs-column' : ''}{direction == 'column-reverse' ? ' MuiGrid-direction-xs-column-reverse' : ''}{size == 1 ? ' MuiGrid-grid-xs-1' : ''}{size == 2 ? ' MuiGrid-grid-xs-2' : ''}{size == 3 ? ' MuiGrid-grid-xs-3' : ''}{size == 4 ? ' MuiGrid-grid-xs-4' : ''}{size == 5 ? ' MuiGrid-grid-xs-5' : ''}{size == 6 ? ' MuiGrid-grid-xs-6' : ''}{size == 7 ? ' MuiGrid-grid-xs-7' : ''}{size == 8 ? ' MuiGrid-grid-xs-8' : ''}{size == 9 ? ' MuiGrid-grid-xs-9' : ''}{size == 10 ? ' MuiGrid-grid-xs-10' : ''}{size == 11 ? ' MuiGrid-grid-xs-11' : ''}{size == 12 ? ' MuiGrid-grid-xs-12' : ''}{container && spacing == 1 ? ' MuiGrid-spacing-xs-1' : ''}{container && spacing == 2 ? ' MuiGrid-spacing-xs-2' : ''}{container && spacing == 3 ? ' MuiGrid-spacing-xs-3' : ''}{container && spacing == 4 ? ' MuiGrid-spacing-xs-4' : ''}{container && spacing == 5 ? ' MuiGrid-spacing-xs-5' : ''}{container && spacing == 6 ? ' MuiGrid-spacing-xs-6' : ''}{container && spacing == 7 ? ' MuiGrid-spacing-xs-7' : ''}{container && spacing == 8 ? ' MuiGrid-spacing-xs-8' : ''}{container && spacing == 9 ? ' MuiGrid-spacing-xs-9' : ''}{container && spacing == 10 ? ' MuiGrid-spacing-xs-10' : ''}{container && spacing == 11 ? ' MuiGrid-spacing-xs-11' : ''}{container && spacing == 12 ? ' MuiGrid-spacing-xs-12' : ''} {className}">
        \\    <Slot />
        \\  </div>
        \\  !className !className_len !columns !columnSpacing !container !direction !direction_len !offset !rowSpacing !size !spacing !wrap !wrap_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[1]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "load state+Grid_wrap as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "load state+Grid_direction as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "load state+Grid_size as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "load state+Grid_spacing as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "load state+Grid_container as i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\" MuiGrid-wrap-xs-wrap-reverse\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\" MuiGrid-direction-xs-row-reverse\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\" MuiGrid-grid-xs-6\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\" MuiGrid-spacing-xs-2\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_str_prop(node_0,"));
}

test "lowerer accepts MobileStepper ownerState variant class templates" {
    const source =
        \\<Component name="MobileStepper">
        \\  <state>
        \\    activeStep = 0
        \\    position = 'bottom' as ptr
        \\    position_len = 6
        \\    steps = 1
        \\    variant = 'dots' as ptr
        \\    variant_len = 4
        \\  </state>
        \\  <div className="MuiPaper-root MuiPaper-elevation MuiPaper-elevation0 MuiMobileStepper-root{position == 'top' ? ' MuiMobileStepper-positionTop' : ''}{position == 'bottom' ? ' MuiMobileStepper-positionBottom' : ''}{position == 'static' ? ' MuiMobileStepper-positionStatic' : ''}">
        \\    <div className=" {variant == 'dots' ? 'MuiMobileStepper-dots' : ''}">
        \\      <div className="MuiMobileStepper-dot MuiMobileStepper-dotActive" />
        \\      <div className="MuiMobileStepper-dot" />
        \\    </div>
        \\    <div className="MuiLinearProgress-root{variant == 'progress' ? ' MuiMobileStepper-progress' : ''}">
        \\      <div className="MuiLinearProgress-bar MuiLinearProgress-bar1" />
        \\    </div>
        \\  </div>
        \\  !activeStep !position !position_len !steps !variant !variant_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"MuiMobileStepper-dots\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\" MuiMobileStepper-progress\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_str_prop(node_0,"));
}

test "lowerer accepts JSX braced attrs and boolean shorthand props" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    count = 7
        \\  </state>
        \\  <input value={count} disabled />
        \\  <Badge count={count} active />
        \\  !count
        \\</Component>
        \\<Component name="Badge">
        \\  <state>
        \\    count = 0
        \\    active = 0 as i1
        \\  </state>
        \\  <span>{count}</span>
        \\  !count !active
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var app_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer app_lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try app_lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_disabled(node_0, 1)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_value(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_badge_set_count(node_1,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_badge_set_active(node_1, 1)"));
}

test "lowerer accepts boolean literal interpolations for user component props" {
    const source =
        \\<Component name="App">
        \\  <Alert icon={false} />
        \\</Component>
        \\<Component name="Alert">
        \\  <state>
        \\    icon = 1 as i1
        \\  </state>
        \\  <div>{icon}</div>
        \\  !icon
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var app_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer app_lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try app_lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_alert_set_icon(node_0, 0)"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "UnknownStateVar") == null);
}

test "lowerer emits controlled value property updates for form elements" {
    const source =
        \\<Component name="FormLab">
        \\  <state>
        \\    count = 7
        \\    label = alloc 32
        \\    label_len = 0
        \\  </state>
        \\  <input value="literal" />
        \\  <input value={count} />
        \\  <textarea value="Label {label}" />
        \\  <select value={label}></select>
        \\  <meter value={count}></meter>
        \\  !count !label !label_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 7, "call @sax_dom_set_value(node_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_value(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_value(node_1,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_value(node_2,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_value(node_3,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_value(node_4,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_str_prop(node_4,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_attr(node_4,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "attr_tpl_node_2_value_buf = stack_alloc"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "attr_str_node_3_value_ptr = load state+FormLab_label as ptr"));
}

test "lowerer maps textarea children to value property when value attr is absent" {
    const source =
        \\<Component name="TextareaLab">
        \\  <state>
        \\    label = alloc 32
        \\    label_len = 0
        \\  </state>
        \\  <textarea>Plain {label}</textarea>
        \\  <textarea value="Explicit">Ignored child</textarea>
        \\  !label !label_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_value(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_text(node_0,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_value(node_1,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_text(node_1,") == null);
}

test "lowerer preserves mixed text and element children with text nodes" {
    const source =
        \\<Component name="MixedTextLab">
        \\  <state>
        \\    label = alloc 32
        \\    label_len = 0
        \\  </state>
        \\  <div>{label}<span className="icon" /></div>
        \\  !label !label_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "#def sax_MixedTextLab_node_div_text_0 = +8"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_text(node_0,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_text(text_node_render_0_0,"));

    const text_append = std.mem.indexOf(u8, out.items, "call @sax_dom_append_child(node_0, text_node_0_0)") orelse return error.TestUnexpectedResult;
    const span_append = std.mem.indexOf(u8, out.items, "call @sax_dom_append_child(node_0, node_1)") orelse return error.TestUnexpectedResult;
    try std.testing.expect(text_append < span_append);
}

test "lowerer treats defaultValue as initial-only form value" {
    const source =
        \\<Component name="DefaultValueLab">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\  <input defaultValue="seed" />
        \\  <textarea defaultValue="initial">Ignored child</textarea>
        \\  <select defaultValue="secondary">
        \\    <option value="primary">Primary</option>
        \\    <option value="secondary">Secondary</option>
        \\  </select>
        \\  <select multiple defaultValue="alpha,beta">
        \\    <option value="alpha">Alpha</option>
        \\    <option value="beta">Beta</option>
        \\    <option value="gamma">Gamma</option>
        \\  </select>
        \\  <p>{count}</p>
        \\  @inc:
        \\  L_ENTRY:
        \\    count = load state+DefaultValueLab_count as i64
        \\    count = add count, 1
        \\    store state+DefaultValueLab_count, count as i64
        \\    call @render()
        \\    ret
        \\  !count
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_value(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_value(node_1,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_value(node_2,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_value(node_5,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_text(node_1,") == null);
    try std.testing.expect((std.mem.indexOf(u8, out.items, "call @sax_dom_append_child(node_2, node_4)") orelse return error.TestUnexpectedResult) <
        (std.mem.indexOf(u8, out.items, "call @sax_dom_set_value(node_2,") orelse return error.TestUnexpectedResult));
    try std.testing.expect((std.mem.indexOf(u8, out.items, "call @sax_dom_append_child(node_5, node_8)") orelse return error.TestUnexpectedResult) <
        (std.mem.indexOf(u8, out.items, "call @sax_dom_set_value(node_5,") orelse return error.TestUnexpectedResult));

    const inc_start = std.mem.indexOf(u8, out.items, "@ffi_wrapper sax_defaultvaluelab_inc_ffi(ctx: ptr):") orelse return error.TestUnexpectedResult;
    const inc_end = std.mem.indexOf(u8, out.items[inc_start..], "@export sax_defaultvaluelab_destroy(ctx: ptr):") orelse out.items.len - inc_start;
    const inc_block = out.items[inc_start .. inc_start + inc_end];
    try std.testing.expect(std.mem.indexOf(u8, inc_block, "call @sax_dom_set_value(node_0,") == null);
    try std.testing.expect(std.mem.indexOf(u8, inc_block, "call @sax_dom_set_value(node_1,") == null);
    try std.testing.expect(std.mem.indexOf(u8, inc_block, "call @sax_dom_set_value(node_2,") == null);
    try std.testing.expect(std.mem.indexOf(u8, inc_block, "call @sax_dom_set_value(node_5,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, inc_block, 1, "call @sax_dom_set_text(node_9,"));
}

test "lowerer emits autofocus bridge after mount" {
    const source =
        \\<Component name="FocusLab">
        \\  <state>
        \\    active = 1 as i1
        \\  </state>
        \\  <main>
        \\    <input autoFocus />
        \\  </main>
        \\  !active
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_focus(node_h: i64) -> void"));
    const append_pos = std.mem.indexOf(u8, out.items, "call @sax_dom_append_child(host, node_0)") orelse return error.TestUnexpectedResult;
    const focus_pos = std.mem.indexOf(u8, out.items, "call @sax_dom_focus(node_1)") orelse return error.TestUnexpectedResult;
    try std.testing.expect(focus_pos > append_pos);
}

test "lowerer emits controlled checked property updates for input elements" {
    const source =
        \\<Component name="CheckLab">
        \\  <state>
        \\    active = 1 as i1
        \\    count = 0
        \\  </state>
        \\  <input type="checkbox" checked />
        \\  <input type="checkbox" checked="false" />
        \\  <input type="checkbox" checked={active} />
        \\  <div checked></div>
        \\  !active !count
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_checked(node_h: i64, checked: i1) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_checked(node_0, 1)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_checked(node_1, 0)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_checked(node_2,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = load state+CheckLab_active as i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = zext "));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_checked(node_3,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_attr(node_3,"));
}

test "lowerer treats defaultChecked as initial-only checked state" {
    const source =
        \\<Component name="DefaultCheckedLab">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\  <input type="checkbox" defaultChecked />
        \\  <p>{count}</p>
        \\  @inc:
        \\  L_ENTRY:
        \\    count = load state+DefaultCheckedLab_count as i64
        \\    count = add count, 1
        \\    store state+DefaultCheckedLab_count, count as i64
        \\    call @render()
        \\    ret
        \\  !count
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_checked(node_0, 1)"));
    const inc_start = std.mem.indexOf(u8, out.items, "@ffi_wrapper sax_defaultcheckedlab_inc_ffi(ctx: ptr):") orelse return error.TestUnexpectedResult;
    const inc_end = std.mem.indexOf(u8, out.items[inc_start..], "@export sax_defaultcheckedlab_destroy(ctx: ptr):") orelse out.items.len - inc_start;
    const inc_block = out.items[inc_start .. inc_start + inc_end];
    try std.testing.expect(std.mem.indexOf(u8, inc_block, "call @sax_dom_set_checked(node_0,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, inc_block, 1, "call @sax_dom_set_text(node_1,"));
}

test "lowerer emits selected property updates for option elements" {
    const source =
        \\<Component name="SelectLab">
        \\  <state>
        \\    active = 1 as i1
        \\  </state>
        \\  <select value="advanced">
        \\    <option value="basic" selected="false">Basic</option>
        \\    <option value="advanced" defaultSelected>Advanced</option>
        \\    <option value="dynamic" selected={active}>Dynamic</option>
        \\  </select>
        \\  <div selected></div>
        \\  !active
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_selected(node_h: i64, selected: i1) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_selected(node_1, 0)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_selected(node_2, 1)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_selected(node_3,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = load state+SelectLab_active as i1"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_selected(node_4,") == null);
    const render_start = std.mem.indexOf(u8, out.items, "@ffi_wrapper sax_selectlab_render_ffi(ctx: ptr):") orelse return error.TestUnexpectedResult;
    const render_end = std.mem.indexOf(u8, out.items[render_start..], "@export sax_selectlab_destroy(ctx: ptr):") orelse out.items.len - render_start;
    const render_block = out.items[render_start .. render_start + render_end];
    try std.testing.expect(std.mem.indexOf(u8, render_block, "call @sax_dom_set_selected(node_2,") == null);
}

test "lowerer emits option and optgroup label property updates" {
    const source =
        \\<Component name="OptionLabelLab">
        \\  <select>
        \\    <optgroup label="Grouped choices">
        \\      <option value="basic" label="Basic option">Basic</option>
        \\    </optgroup>
        \\  </select>
        \\  <div label="ignored"></div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"label\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"value\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_str_prop(node_1,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_str_prop(node_2,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_3,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_attr(node_3,"));
}

test "lowerer emits multiple property updates for select and input elements" {
    const source =
        \\<Component name="MultiLab">
        \\  <state>
        \\    enabled = 1 as i1
        \\  </state>
        \\  <select multiple></select>
        \\  <select multiple="false"></select>
        \\  <select multiple={enabled}></select>
        \\  <input type="file" multiple />
        \\  <input type="email" multiple={enabled} />
        \\  <div multiple></div>
        \\  !enabled
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_multiple(node_h: i64, multiple: i1) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_multiple(node_0, 1)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_multiple(node_1, 0)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_multiple(node_2,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, " = load state+MultiLab_enabled as i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_multiple(node_3, 1)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_multiple(node_4,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_multiple(node_5,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_attr(node_5,"));
}

test "lowerer emits disabled property updates for form control elements" {
    const source =
        \\<Component name="DisabledLab">
        \\  <state>
        \\    locked = 1 as i1
        \\  </state>
        \\  <button disabled>Save</button>
        \\  <input disabled="false" />
        \\  <select disabled={locked}></select>
        \\  <div disabled></div>
        \\  !locked
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_disabled(node_h: i64, disabled: i1) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_disabled(node_0, 1)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_disabled(node_1, 0)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_disabled(node_2,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_disabled(node_3,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_attr(node_3,"));
}

test "lowerer emits readonly property updates for text controls" {
    const source =
        \\<Component name="ReadonlyLab">
        \\  <state>
        \\    locked = 1 as i1
        \\  </state>
        \\  <input readOnly />
        \\  <textarea readOnly="false"></textarea>
        \\  <input readOnly={locked} />
        \\  <div readOnly></div>
        \\  !locked
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_readonly(node_h: i64, readonly: i1) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_readonly(node_0, 1)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_readonly(node_1, 0)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_readonly(node_2,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_readonly(node_3,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_attr(node_3,"));
}

test "lowerer emits required property updates for form value controls" {
    const source =
        \\<Component name="RequiredLab">
        \\  <state>
        \\    needed = 1 as i1
        \\  </state>
        \\  <input required />
        \\  <select required="false"></select>
        \\  <textarea required={needed}></textarea>
        \\  <button required>Send</button>
        \\  !needed
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_required(node_h: i64, required: i1) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_required(node_0, 1)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_required(node_1, 0)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_required(node_2,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_required(node_3,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_attr(node_3,"));
}

test "lowerer emits open property updates for disclosure elements" {
    const source =
        \\<Component name="OpenLab">
        \\  <state>
        \\    visible = 1 as i1
        \\  </state>
        \\  <dialog open></dialog>
        \\  <details open="false"></details>
        \\  <dialog open={visible}></dialog>
        \\  <div open></div>
        \\  !visible
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_open(node_h: i64, open: i1) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_open(node_0, 1)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_open(node_1, 0)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_open(node_2,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_open(node_3,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_attr(node_3,"));
}

test "lowerer emits generic React boolean DOM property updates" {
    const source =
        \\<Component name="BoolPropLab">
        \\  <state>
        \\    enabled = 1
        \\  </state>
        \\  <video controls muted="false" loop={enabled} autoPlay playsInline disablePictureInPicture disableRemotePlayback></video>
        \\  <track default></track>
        \\  <form noValidate></form>
        \\  <button formNoValidate>Submit</button>
        \\  <ol reversed></ol>
        \\  <div hidden inert={enabled} draggable itemScope></div>
        \\  <img isMap />
        \\  <link disabled />
        \\  <section controls></section>
        \\  !enabled
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_bool_prop(node_h: i64, *prop_ptr: ptr, prop_len: i64, value: i1) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "utf8:\"controls\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"muted\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"loop\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"autoplay\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"playsInline\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"disablePictureInPicture\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"disableRemotePlayback\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"noValidate\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"formNoValidate\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"reversed\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"default\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"hidden\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"inert\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"draggable\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"itemScope\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"isMap\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"disabled\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 20, "call @sax_dom_set_bool_prop("));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_bool_prop(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_bool_prop(node_1,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_bool_prop(node_2,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_bool_prop(node_3,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_bool_prop(node_4,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_bool_prop(node_6,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_bool_prop(node_7,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_bool_prop(node_8,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_attr(node_8,"));
}

test "lowerer emits generic React string DOM property updates for native controls" {
    const source =
        \\<Component name="StringPropLab">
        \\  <state>
        \\    high = 100
        \\  </state>
        \\  <input type="range" min="0" max={high} step="5" size="12" placeholder="Type" pattern="[0-9]+" accept="text/plain" capture="environment" dirName="input.dir" maxLength="24" minLength="3" inputMode="numeric" enterKeyHint="done" autoCapitalize="none" autoCorrect="off" />
        \\  <textarea rows="4" cols="24" wrap="soft" placeholder="Notes" dirName="notes.dir" maxLength="80" minLength="5"></textarea>
        \\  <select size="3" autoComplete="country-name"></select>
        \\  <meter min="0" max="100" low="25" high={high} optimum="60" value="50"></meter>
        \\  <progress max="100" value="35"></progress>
        \\  <div contentEditable="true" spellCheck="false" inputMode="text" enterKeyHint="send" autoCapitalize="sentences" autoCorrect="on"></div>
        \\  <img width="320" height="180" loading="lazy" decoding="async" fetchPriority="high" />
        \\  <video width="640" height="360"></video>
        \\  <canvas width="300" height="150"></canvas>
        \\  <ol start="3"><li value="5">Fifth</li></ol>
        \\  <blockquote cite="/quotes/source"><q cite="/quotes/inline">Quoted</q><del cite="/edits/old" dateTime="2026-01-01">Old</del><ins cite="/edits/new" dateTime="2026-01-02">New</ins></blockquote>
        \\  <div min="0" max="100"></div>
        \\  !high
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_str_prop(node_h: i64, *prop_ptr: ptr, prop_len: i64, *val_ptr: ptr, val_len: i64) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"min\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"max\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"step\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"low\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"high\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"optimum\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "utf8:\"value\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"size\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"maxLength\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"minLength\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"rows\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"cols\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"wrap\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"placeholder\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"pattern\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"accept\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"capture\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"dirName\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "utf8:\"inputMode\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "utf8:\"enterKeyHint\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "utf8:\"autoCapitalize\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "utf8:\"autocorrect\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"contentEditable\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"spellcheck\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 3, "utf8:\"width\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 3, "utf8:\"height\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"start\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 4, "utf8:\"cite\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "utf8:\"dateTime\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"loading\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"decoding\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"fetchPriority\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 30, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 14, "call @sax_dom_set_str_prop(node_1,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 4, "call @sax_dom_set_str_prop(node_2,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 12, "call @sax_dom_set_str_prop(node_3,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 4, "call @sax_dom_set_str_prop(node_4,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 12, "call @sax_dom_set_str_prop(node_5,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 10, "call @sax_dom_set_str_prop(node_6,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 4, "call @sax_dom_set_str_prop(node_7,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 4, "call @sax_dom_set_str_prop(node_8,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_str_prop(node_9,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_str_prop(node_10,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_str_prop(node_11,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_str_prop(node_12,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 4, "call @sax_dom_set_str_prop(node_13,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 4, "call @sax_dom_set_str_prop(node_14,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_value(node_10,") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_15,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_attr(node_15,"));
}

test "lowerer emits image submit input reflected DOM property updates" {
    const source =
        \\<Component name="ImageInputLab">
        \\  <input type="image" src="/submit.png" alt="Submit image" width="32" height="24" />
        \\  <div src="/plain.png" alt="Plain" width="1" height="1"></div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_str_prop(node_h: i64, *prop_ptr: ptr, prop_len: i64, *val_ptr: ptr, val_len: i64) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"type\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"src\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"alt\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"width\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"height\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 10, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_1,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 4, "call @sax_dom_set_attr(node_1,"));
}

test "lowerer emits image map area reflected DOM property updates" {
    const source =
        \\<Component name="AreaPropLab">
        \\  <map name="avatar-map"><area alt="Avatar area" coords="0,0,32,32" shape="rect" href="/profile" hrefLang="en" download="profile.txt" rel="nofollow" target="_self" referrerPolicy="no-referrer" /></map>
        \\  <div alt="Plain" href="/plain"></div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"alt\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"coords\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"shape\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"href\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"hreflang\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"download\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"rel\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"target\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"referrerPolicy\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 18, "call @sax_dom_set_str_prop(node_1,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_2,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_attr(node_2,"));
}

test "lowerer emits image longDesc reflected DOM property updates" {
    const source =
        \\<Component name="ImageLongDescLab">
        \\  <img src="/preview.png" longDesc="/preview-description" />
        \\  <div longDesc="/plain-description"></div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"src\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"longDesc\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 4, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_1,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_attr(node_1,"));
}

test "lowerer emits data element value reflected DOM property updates" {
    const source =
        \\<Component name="DataValueLab">
        \\  <data value="product-42">Product 42</data>
        \\  <div value="plain">Plain</div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_str_prop(node_h: i64, *prop_ptr: ptr, prop_len: i64, *val_ptr: ptr, val_len: i64) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"value\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_1,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_attr(node_1,"));
}

test "lowerer emits param value reflected DOM property updates" {
    const source =
        \\<Component name="ParamValueLab">
        \\  <param name="quality" value="high" />
        \\  <div value="plain">Plain</div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_str_prop(node_h: i64, *prop_ptr: ptr, prop_len: i64, *val_ptr: ptr, val_len: i64) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"value\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_1,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_attr(node_1,"));
}

test "lowerer emits base href and target reflected DOM property updates" {
    const source =
        \\<Component name="BasePropLab">
        \\  <base href="/docs/" target="_self" />
        \\  <div href="/plain" target="_blank">Plain</div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_str_prop(node_h: i64, *prop_ptr: ptr, prop_len: i64, *val_ptr: ptr, val_len: i64) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"href\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"target\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 4, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_1,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_attr(node_1,"));
}

test "lowerer emits ordered list type reflected DOM property updates" {
    const source =
        \\<Component name="OlTypeLab">
        \\  <ol type="A"><li>Alpha</li></ol>
        \\  <ul type="disc"><li>Plain</li></ul>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_str_prop(node_h: i64, *prop_ptr: ptr, prop_len: i64, *val_ptr: ptr, val_len: i64) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"type\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_2,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_attr(node_2,"));
}

test "lowerer emits output htmlFor reflected DOM property updates" {
    const source =
        \\<Component name="OutputForLab">
        \\  <output htmlFor="amount-input">42</output>
        \\  <div htmlFor="plain">Plain</div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_str_prop(node_h: i64, *prop_ptr: ptr, prop_len: i64, *val_ptr: ptr, val_len: i64) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"htmlFor\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_1,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_attr(node_1,"));
}

test "lowerer emits meta httpEquiv and content reflected DOM property updates" {
    const source =
        \\<Component name="MetaPropLab">
        \\  <meta httpEquiv="refresh" content="30" />
        \\  <div httpEquiv="ignored" content="plain">Plain</div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_str_prop(node_h: i64, *prop_ptr: ptr, prop_len: i64, *val_ptr: ptr, val_len: i64) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"httpEquiv\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"content\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 4, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_1,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_attr(node_1,"));
}

test "lowerer emits style media and type reflected DOM property updates" {
    const source =
        \\<Component name="StylePropLab">
        \\  <style media="screen" type="text/css"></style>
        \\  <div media="print">Plain</div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_str_prop(node_h: i64, *prop_ptr: ptr, prop_len: i64, *val_ptr: ptr, val_len: i64) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"media\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"type\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 4, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_1,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_attr(node_1,"));
}

test "lowerer emits reflected React string DOM property updates" {
    const source =
        \\<Component name="ReflectedPropLab">
        \\  <div className="tooltip-host" id="tooltip-host" name="tooltip" nonce="nonce-123" title="Helpful tooltip" lang="en" dir="rtl" role="note" accessKey="k" tabIndex="2" slot="toolbar" part="panel" popover="auto" itemProp="name" itemType="https://schema.org/Thing" itemID="thing-1" itemRef="thing-ref">Tooltip host</div>
        \\  <label htmlFor="name-input">Name</label>
        \\  <colgroup span="2" width="120"><col span="1" width="80" /></colgroup>
        \\  <td rowSpan="2" colSpan="3" headers="h-name" width="240" height="48">Cell</td>
        \\  <th scope="col" abbr="Nm" headers="h-group" width="120" height="32">Name</th>
        \\  <time dateTime="2026-06-08">Today</time>
        \\  <meta charSet="utf-8" />
        \\  <img alt="Preview" srcSet="a.png 1x, a2.png 2x" sizes="(min-width: 800px) 50vw, 100vw" useMap="#map" crossOrigin="anonymous" referrerPolicy="no-referrer" />
        \\  <form acceptCharset="utf-8" encType="multipart/form-data" method="post" rel="noopener" target="_self" autoComplete="off">
        \\    <button type="submit" value="save-action" formAction="/save" formEncType="text/plain" formMethod="post" formTarget="_blank">Save</button>
        \\  </form>
        \\  <input type="email" />
        \\  <div htmlFor="ignored"></div>
        \\  <div type="ignored" rel="ignored"></div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"className\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"id\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"name\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"nonce\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"title\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"lang\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"dir\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"role\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"accessKey\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"tabIndex\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"slot\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"part\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"popover\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"itemProp\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"itemType\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"itemID\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"itemRef\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"htmlFor\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"rowSpan\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"colSpan\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "utf8:\"headers\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"scope\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"abbr\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "utf8:\"span\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 4, "utf8:\"width\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "utf8:\"height\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"dateTime\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"charset\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"alt\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"srcset\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"sizes\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"useMap\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"crossOrigin\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 3, "utf8:\"referrerPolicy\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"acceptCharset\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"rel\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "utf8:\"type\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"save-action\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"formAction\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"formEnctype\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"formMethod\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"formTarget\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 50, "call @sax_dom_set_str_prop("));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_12,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_attr(node_12,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_13,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_attr(node_13,"));
}

test "lowerer emits URL and media reflected string DOM property updates" {
    const source =
        \\<Component name="UrlPropLab">
        \\  <a href="/report" charSet="utf-8" hrefLang="en" download="report.txt" rel="noopener" type="text/plain" target="_blank" referrerPolicy="origin">Report</a>
        \\  <link rel="preload" href="hero.avif" hrefLang="en-US" charSet="utf-8" as="image" media="screen" type="image/avif" imageSrcSet="hero.avif 1x, hero@2x.avif 2x" imageSizes="100vw" integrity="sha256-demo" fetchPriority="high" crossOrigin="anonymous" referrerPolicy="no-referrer" />
        \\  <video src="movie.mp4" poster="poster.png" preload="metadata" crossOrigin="anonymous" controlsList="nodownload"></video>
        \\  <audio src="sound.mp3" preload="auto" crossOrigin="anonymous"></audio>
        \\  <source src="movie.webm" type="video/webm" media="(min-width: 1px)" srcSet="movie.webm 1x" width="320" height="180" />
        \\  <track src="captions.vtt" kind="captions" srcLang="en" label="English captions" />
        \\  <form action="/submit"></form>
        \\  <div href="/ignored" width="1" height="1" charSet="utf-8" imageSrcSet="ignored 1x" imageSizes="1px" fetchPriority="low"></div>
        \\  <area type="ignored" />
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"href\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "utf8:\"hreflang\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "utf8:\"charset\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"download\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"rel\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"as\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"media\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"integrity\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"imageSrcset\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"imageSizes\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"fetchPriority\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "utf8:\"referrerPolicy\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"src\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"poster\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"preload\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"controlsList\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"width\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"height\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 3, "utf8:\"type\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"kind\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"srcLang\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"label\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"action\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_str_prop(node_1,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_str_prop(node_2,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_str_prop(node_3,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 12, "call @sax_dom_set_str_prop(node_4,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_str_prop(node_5,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 28, "call @sax_dom_set_str_prop("));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_7,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 5, "call @sax_dom_set_attr(node_7,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_8,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_attr(node_8,"));
}

test "lowerer emits anchor and area ping reflected DOM property updates" {
    const source =
        \\<Component name="PingPropLab">
        \\  <a ping="/audit /metrics">Report</a>
        \\  <area href="/profile" ping="/map-ping" />
        \\  <div ping="/plain-ping"></div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "utf8:\"ping\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_str_prop(node_1,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_2,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_attr(node_2,"));
}

test "lowerer emits anchor coords and shape reflected DOM property updates" {
    const source =
        \\<Component name="AnchorGeometryPropLab">
        \\  <a coords="0,0,32,32" shape="rect">Mapped report</a>
        \\  <div coords="1,1,2,2" shape="circle"></div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"coords\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"shape\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_1,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 2, "call @sax_dom_set_attr(node_1,"));
}

test "lowerer emits link sizes reflected DOM property updates" {
    const source =
        \\<Component name="LinkSizesPropLab">
        \\  <link rel="icon" href="/favicon.svg" sizes="any" />
        \\  <div sizes="1px"></div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"sizes\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 3, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_1,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_attr(node_1,"));
}

test "lowerer emits link target reflected DOM property updates" {
    const source =
        \\<Component name="LinkTargetPropLab">
        \\  <link rel="help" href="/help" target="_blank" />
        \\  <section target="_self"></section>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"target\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 3, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_1,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_attr(node_1,"));
}

test "lowerer emits link blocking reflected DOM property updates" {
    const source =
        \\<Component name="LinkBlockingPropLab">
        \\  <link rel="stylesheet" href="/app.css" blocking="render" />
        \\  <div blocking="render"></div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"blocking\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 3, "call @sax_dom_set_str_prop(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_str_prop(node_1,") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_attr(node_1,"));
}

test "lowerer emits translate DOM property updates" {
    const source =
        \\<Component name="TranslatePropLab">
        \\  <state>
        \\    mode = 0
        \\  </state>
        \\  <div translate="no">Disabled translation</div>
        \\  <div translate={mode}>Interpolated translation</div>
        \\  <div translate="state-{mode}">Template translation</div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_translate(node_h: i64, *val_ptr: ptr, val_len: i64) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"no\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 3, "call @sax_dom_set_translate("));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_translate(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_translate(node_1,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_translate(node_2,"));
}

test "lowerer binds React-style event handler references" {
    const source =
        \\<Component name="EventLab">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\  <button onClick={inc}>+1</button>
        \\  @inc:
        \\  L_ENTRY:
        \\    count = load state+EventLab_count as i64
        \\    count = add count, 1
        \\    store state+EventLab_count, count as i64
        \\    call @render()
        \\    ret
        \\  !count
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"click\""));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"onclick\"") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_bind_event(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@export sax_eventlab_inc(ctx: ptr):"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_target() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_target_value(*buf_ptr: ptr, buf_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_target_checked() -> i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_target_name(*buf_ptr: ptr, buf_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_target_id(*buf_ptr: ptr, buf_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_key(*buf_ptr: ptr, buf_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_code(*buf_ptr: ptr, buf_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_repeat() -> i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_type(*buf_ptr: ptr, buf_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_data(*buf_ptr: ptr, buf_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_input_type(*buf_ptr: ptr, buf_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_time_stamp() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_current_target() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_current_target_value(*buf_ptr: ptr, buf_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_current_target_checked() -> i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_current_target_name(*buf_ptr: ptr, buf_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_current_target_id(*buf_ptr: ptr, buf_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_related_target() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_related_target_name(*buf_ptr: ptr, buf_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_related_target_id(*buf_ptr: ptr, buf_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_default_prevented() -> i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_button() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_client_x() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_client_y() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_page_x() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_page_y() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_screen_x() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_screen_y() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_pointer_id() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_pointer_type(*buf_ptr: ptr, buf_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_is_primary() -> i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_delta_x() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_delta_y() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_delta_z() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_delta_mode() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_touches_len() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_touch_identifier() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_touch_client_x() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_touch_client_y() -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_clipboard_text(*buf_ptr: ptr, buf_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_data_transfer_text(*buf_ptr: ptr, buf_len: i64) -> i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_shift_key() -> i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_ctrl_key() -> i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_alt_key() -> i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_meta_key() -> i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_prevent_default() -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_event_stop_propagation() -> void"));
}

test "lowerer keeps ptr state setter forward decls from colliding with handlers" {
    const source =
        \\<Component name="App">
        \\  <state>
        \\    status_fallback = alloc 64
        \\    status_fallback_len = 0
        \\  </state>
        \\  <input value={status_fallback} onChange={set_status_fallback} />
        \\  @set_status_fallback:
        \\  L_ENTRY:
        \\    call @render()
        \\    ret
        \\  !status_fallback !status_fallback_len
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.indexOf(u8, out.items, "@extern sax_app_set_status_fallback(ctx: ptr, value: ptr, value_len: i64) -> void") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_app_set_status_fallback_str(ctx: ptr, *value: ptr, value_len: i64) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@export sax_app_set_status_fallback(ctx: ptr):"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_bind_event(node_0,"));
}

test "lowerer binds React capture event handlers with DOM event names" {
    const source =
        \\<Component name="CaptureLab">
        \\  <button onClickCapture={capture}>Capture</button>
        \\  @capture:
        \\  L_ENTRY:
        \\    ret
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_bind_event_capture"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"click\""));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"clickcapture\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"onclickcapture\"") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_bind_event_capture(node_0,"));
}

test "lowerer maps React onDoubleClick to DOM dblclick events" {
    const source =
        \\<Component name="DoubleClickLab">
        \\  <button onDoubleClick={press} onDoubleClickCapture={capture}>Double</button>
        \\  @press:
        \\  L_ENTRY:
        \\    ret
        \\  @capture:
        \\  L_ENTRY:
        \\    ret
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"dblclick\""));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"doubleclick\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"doubleclickcapture\"") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_bind_event(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_bind_event_capture(node_0,"));
}

test "lowerer maps React mouse enter and leave capture aliases to DOM events" {
    const source =
        \\<Component name="MouseBoundaryLab">
        \\  <div onMouseEnter={enter} onMouseLeaveCapture={leave}>Boundary</div>
        \\  @enter:
        \\  L_ENTRY:
        \\    ret
        \\  @leave:
        \\  L_ENTRY:
        \\    ret
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"mouseenter\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"mouseleave\""));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"mouseentercapture\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"mouseleavecapture\"") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_bind_event(node_0,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_bind_event_capture(node_0,"));
}

test "lowerer maps synthetic onClickAway to click away binding" {
    const source =
        \\<Component name="App">
        \\  <Action onClickAway={close_menu}>Projected</Action>
        \\  @close_menu:
        \\  L_ENTRY:
        \\    ret
        \\</Component>
        \\<Component name="Action">
        \\  <div><Slot /></div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    for (program.components, 0..) |component, idx| {
        var component_lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, component);
        defer component_lowerer.deinit();
        try component_lowerer.lower(&out, .{ .emit_shared_decls = idx == 0 });
    }

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"clickaway\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_bind_event(node_0_root,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@export sax_app_close_menu(ctx: ptr):"));
}

test "lowerer stores DOM handles for state refs on mount" {
    const source =
        \\<Component name="RefLab">
        \\  <state>
        \\    input_ref = 0
        \\    count = 0
        \\  </state>
        \\  <input ref={input_ref} value={count} />
        \\  @inc:
        \\  L_ENTRY:
        \\    count = load state+RefLab_count as i64
        \\    count = add count, 1
        \\    store state+RefLab_count, count as i64
        \\    call @render()
        \\    ret
        \\  !input_ref !count
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "store state+RefLab_input_ref, node_0 as i64"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"ref\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_attr(node_0, *") == null);

    const inc_start = std.mem.indexOf(u8, out.items, "@ffi_wrapper sax_reflab_inc_ffi(ctx: ptr):") orelse return error.TestUnexpectedResult;
    const inc_end = std.mem.indexOf(u8, out.items[inc_start..], "@export sax_reflab_destroy(ctx: ptr):") orelse out.items.len - inc_start;
    const inc_block = out.items[inc_start .. inc_start + inc_end];
    try std.testing.expect(std.mem.indexOf(u8, inc_block, "store state+RefLab_input_ref") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, inc_block, 1, "call @sax_dom_set_value(node_0,"));
}

test "lowerer stores user component contexts for state refs on mount" {
    const source =
        \\<Component name="RefLab">
        \\  <state>
        \\    child_ref = 0 as ptr
        \\    count = 0
        \\  </state>
        \\  <Child ref={child_ref} />
        \\  @inc:
        \\  L_ENTRY:
        \\    count = load state+RefLab_count as i64
        \\    count = add count, 1
        \\    store state+RefLab_count, count as i64
        \\    call @render()
        \\    ret
        \\  !count
        \\</Component>
        \\
        \\<Component name="Child">
        \\  <div>Child</div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "node_0 = call @sax_child_mount(host)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "store state+RefLab_child_ref, node_0 as ptr"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"ref\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "set_ref") == null);

    const inc_start = std.mem.indexOf(u8, out.items, "@ffi_wrapper sax_reflab_inc_ffi(ctx: ptr):") orelse return error.TestUnexpectedResult;
    const inc_end = std.mem.indexOf(u8, out.items[inc_start..], "@export sax_reflab_destroy(ctx: ptr):") orelse out.items.len - inc_start;
    const inc_block = out.items[inc_start .. inc_start + inc_end];
    try std.testing.expect(std.mem.indexOf(u8, inc_block, "store state+RefLab_child_ref") == null);
}

test "lowerer invokes callback refs on mount and destroy" {
    const source =
        \\<Component name="RefCallback">
        \\  <state>
        \\    dom_seen = 0
        \\    child_seen = 0 as ptr
        \\  </state>
        \\  <input ref={capture_dom} />
        \\  <Child ref={capture_child} />
        \\  @capture_dom:
        \\  L_ENTRY:
        \\    store state+RefCallback_dom_seen, ref_value as i64
        \\    ret
        \\  @capture_child:
        \\  L_ENTRY:
        \\    store state+RefCallback_child_seen, ref_value as ptr
        \\    ret
        \\</Component>
        \\
        \\<Component name="Child">
        \\  <div>Child</div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.initWithProgram(std.testing.allocator, program.components, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@ffi_wrapper sax_refcallback_capture_dom_dom_ref_ffi(ctx: ptr, ref_value: i64):"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@ffi_wrapper sax_refcallback_capture_child_component_ref_ffi(ctx: ptr, ref_value: ptr):"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_refcallback_capture_dom_dom_ref_ffi(ctx, node_0)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "node_1 = call @sax_child_mount(host)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_refcallback_capture_child_component_ref_ffi(ctx, node_1)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "store state+RefCallback_dom_seen, ref_value as i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "store state+RefCallback_child_seen, ref_value as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_refcallback_capture_dom_dom_ref_ffi(ctx, 0)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_refcallback_capture_child_component_ref_ffi(ctx, 0)"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"ref\"") == null);
}

test "lowerer preserves React keys as metadata without DOM attributes" {
    const source =
        \\<Component name="KeyLab">
        \\  <state>
        \\    id = 7
        \\  </state>
        \\  <ul>
        \\    <li key={id}>Item</li>
        \\  </ul>
        \\  !id
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@const sax_KeyLab_key_li = utf8:\"id\""));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"key\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_attr(node_1,") == null);
}

test "lowerer skips React suppress warning props on DOM nodes" {
    const source =
        \\<Component name="SuppressLab">
        \\  <div suppressContentEditableWarning suppressHydrationWarning contentEditable="true">Editable</div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"contentEditable\""));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"suppressContentEditableWarning\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"suppressHydrationWarning\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_attr(node_0, *") == null);
}

test "lowerer maps React onChange to input events for text controls" {
    const source =
        \\<Component name="ChangeLab">
        \\  <input value="a" onChange={changed} />
        \\  <textarea value="b" onChange={changed}></textarea>
        \\  <input type="checkbox" checked onChange={changed} />
        \\  <select value="x" onChange={changed}></select>
        \\  @changed:
        \\  L_ENTRY:
        \\    ret
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"input\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"change\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_bind_event(node_0, *"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_bind_event(node_1, *"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_bind_event(node_2, *"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_bind_event(node_3, *"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"onchange\"") == null);
}

test "lowerer emits static React style object attrs as CSS text" {
    const source =
        \\<Component name="Styled">
        \\  <div style={{ display: "grid", gap: "8px", lineHeight: 1.5 }}></div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"style\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"display: grid; gap: 8px; line-height: 1.5; \""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_attr(node_0,"));
}

test "lowerer emits safe dangerouslySetInnerHTML through dedicated bridge" {
    const source =
        \\<Component name="HtmlLab">
        \\  <div dangerouslySetInnerHTML={{ __html: "<strong>Trusted</strong>" }}>Ignored text</div>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "@extern sax_dom_set_inner_html(node_h: i64, *html_ptr: ptr, html_len: i64) -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"<strong>Trusted</strong>\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_set_inner_html(node_0,"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"dangerouslySetInnerHTML\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call @sax_dom_set_text(node_0,") == null);
}

test "lowerer emits React Fragment tags as DOM fragments" {
    const source =
        \\<Component name="Fragments">
        \\  <Fragment><span>A</span></Fragment>
        \\  <React.Fragment><span>B</span></React.Fragment>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"fragment\""));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"Fragment\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"React.Fragment\"") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_create(*"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_append_child(node_0, node_1)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_append_child(node_2, node_3)"));
}

test "lowerer emits React shorthand Fragment tags as DOM fragments" {
    const source =
        \\<Component name="Fragments">
        \\  <><span>A</span><span>B</span></>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    var lowerer = try SaxLowerer.init(std.testing.allocator, program.components[0]);
    defer lowerer.deinit();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try lowerer.lower(&out, .{});

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "utf8:\"fragment\""));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "utf8:\"Fragment\"") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_append_child(node_0, node_1)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "call @sax_dom_append_child(node_0, node_2)"));
}
