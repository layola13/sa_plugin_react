const std = @import("std");

const Kind = struct {
    const function: u8 = 0;
    const table: u8 = 1;
    const memory: u8 = 2;
    const global: u8 = 3;
};

const Symbol = struct {
    module: []const u8 = "",
    name: []const u8,
    kind: u8,
};

const required_imports = [_]Symbol{
    .{ .module = "env", .name = "malloc", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_query", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_create", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_bind_event", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_append_child", .kind = Kind.function },
    .{ .module = "env", .name = "sax_mem_copy", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_set_text", .kind = Kind.function },
    .{ .module = "env", .name = "sax_itoa", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_remove_self", .kind = Kind.function },
};

const optional_imports = [_]Symbol{
    .{ .module = "env", .name = "sax_dom_set_attr", .kind = Kind.function },
    .{ .module = "env", .name = "sax_ftoa_bits", .kind = Kind.function },
    .{ .module = "env", .name = "sax_json_write_string", .kind = Kind.function },
    .{ .module = "env", .name = "sax_json_write_object_members", .kind = Kind.function },
    .{ .module = "env", .name = "sax_json_normalize_object", .kind = Kind.function },
    .{ .module = "env", .name = "sax_mem_eq", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_target", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_target_value", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_target_checked", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_target_name", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_target_id", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_key", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_code", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_repeat", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_type", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_data", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_input_type", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_time_stamp", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_current_target", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_current_target_value", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_current_target_checked", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_current_target_name", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_current_target_id", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_related_target", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_related_target_name", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_related_target_id", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_set_selected", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_get_selected", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_focus", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_set_multiple", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_get_multiple", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_set_disabled", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_get_disabled", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_set_readonly", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_get_readonly", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_set_required", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_get_required", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_set_open", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_get_open", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_prevent_default", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_stop_propagation", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_default_prevented", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_button", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_client_x", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_client_y", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_page_x", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_page_y", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_screen_x", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_screen_y", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_pointer_id", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_pointer_type", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_is_primary", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_delta_x", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_delta_y", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_delta_z", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_delta_mode", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_touches_len", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_touch_identifier", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_touch_client_x", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_touch_client_y", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_clipboard_text", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_data_transfer_text", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_shift_key", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_ctrl_key", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_alt_key", .kind = Kind.function },
    .{ .module = "env", .name = "sax_event_meta_key", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_set_bool_prop", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_get_bool_prop", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_set_str_prop", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_get_str_prop", .kind = Kind.function },
    .{ .module = "env", .name = "sax_dom_bind_event_capture", .kind = Kind.function },
};

const Found = struct {
    imports: [required_imports.len]bool = [_]bool{false} ** required_imports.len,
    optional_imports: [optional_imports.len]bool = [_]bool{false} ** optional_imports.len,
    memory_export: bool = false,
    app_init_export: bool = false,
    function_exports: []bool,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 3) {
        try std.io.getStdErr().writer().print("usage: {s} <sax-demo-output-dir> <expected-function-export>...\n", .{args[0]});
        return error.InvalidArguments;
    }
    const expected_function_exports = args[2..];

    const wasm_path = try std.fs.path.join(allocator, &.{ args[1], "app.wasm" });
    defer allocator.free(wasm_path);
    const airlock_path = try std.fs.path.join(allocator, &.{ args[1], "airlock.js" });
    defer allocator.free(airlock_path);
    const app_sa_path = try std.fs.path.join(allocator, &.{ args[1], "app.sa" });
    defer allocator.free(app_sa_path);

    const wasm = try std.fs.cwd().readFileAlloc(allocator, wasm_path, 16 * 1024 * 1024);
    defer allocator.free(wasm);
    if (wasm.len < 1024) {
        try std.io.getStdErr().writer().print("SAX demo wasm is unexpectedly small: {d} bytes\n", .{wasm.len});
        return error.InvalidDemoWasm;
    }

    var found = Found{
        .function_exports = try allocator.alloc(bool, expected_function_exports.len),
    };
    defer allocator.free(found.function_exports);
    @memset(found.function_exports, false);
    try scanWasm(wasm, expected_function_exports, &found);
    try reportMissing(&found, expected_function_exports);

    const airlock = try std.fs.cwd().readFileAlloc(allocator, airlock_path, 16 * 1024 * 1024);
    defer allocator.free(airlock);
    if (!std.mem.containsAtLeast(u8, airlock, 1, "malloc(size)") or
        !std.mem.containsAtLeast(u8, airlock, 1, "return _malloc(size);") or
        !std.mem.containsAtLeast(u8, airlock, 1, "free(_ptr)") or
        std.mem.containsAtLeast(u8, airlock, 1, "return BigInt(_malloc(size));"))
    {
        try std.io.getStdErr().writer().writeAll("airlock.js does not expose the expected wasm32 malloc/free imports\n");
        return error.InvalidAirlock;
    }

    const app_sa = try std.fs.cwd().readFileAlloc(allocator, app_sa_path, 16 * 1024 * 1024);
    defer allocator.free(app_sa);
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_set_attr(")) {
        if (!hasOptionalImport(&found, "sax_dom_set_attr")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_set_attr:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_ftoa_bits(")) {
        if (!hasOptionalImport(&found, "sax_ftoa_bits")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_ftoa_bits:function\n");
            return error.MissingWasmSymbol;
        }
        if (!std.mem.containsAtLeast(u8, airlock, 1, "sax_ftoa_bits(value_bits, decimals, buf_ptr, buf_len)")) {
            try std.io.getStdErr().writer().writeAll("airlock.js does not expose sax_ftoa_bits for f64 state formatting\n");
            return error.InvalidAirlock;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_json_write_string(")) {
        if (!hasOptionalImport(&found, "sax_json_write_string")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_json_write_string:function\n");
            return error.MissingWasmSymbol;
        }
        if (!std.mem.containsAtLeast(u8, airlock, 1, "sax_json_write_string(src_ptr, src_len, dst_ptr, dst_len)")) {
            try std.io.getStdErr().writer().writeAll("airlock.js does not expose sax_json_write_string for JSON object props\n");
            return error.InvalidAirlock;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_json_write_object_members(")) {
        if (!hasOptionalImport(&found, "sax_json_write_object_members")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_json_write_object_members:function\n");
            return error.MissingWasmSymbol;
        }
        if (!std.mem.containsAtLeast(u8, airlock, 1, "sax_json_write_object_members(src_ptr, src_len, dst_ptr, dst_len, prefix_comma)")) {
            try std.io.getStdErr().writer().writeAll("airlock.js does not expose sax_json_write_object_members for JSON object prop spreads\n");
            return error.InvalidAirlock;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_json_normalize_object(")) {
        if (!hasOptionalImport(&found, "sax_json_normalize_object")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_json_normalize_object:function\n");
            return error.MissingWasmSymbol;
        }
        if (!std.mem.containsAtLeast(u8, airlock, 1, "sax_json_normalize_object(src_ptr, src_len, dst_ptr, dst_len)")) {
            try std.io.getStdErr().writer().writeAll("airlock.js does not expose sax_json_normalize_object for object prop overwrite normalization\n");
            return error.InvalidAirlock;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_event_target(")) {
        if (!hasOptionalImport(&found, "sax_event_target")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_event_target:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_event_target_value(")) {
        if (!hasOptionalImport(&found, "sax_event_target_value")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_event_target_value:function\n");
            return error.MissingWasmSymbol;
        }
        if (!std.mem.containsAtLeast(u8, airlock, 1, "sax_event_target_value(buf_ptr, buf_len)")) {
            try std.io.getStdErr().writer().writeAll("airlock.js does not expose sax_event_target_value for synthetic event reads\n");
            return error.InvalidAirlock;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_event_target_checked(")) {
        if (!hasOptionalImport(&found, "sax_event_target_checked")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_event_target_checked:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_event_key(")) {
        if (!hasOptionalImport(&found, "sax_event_key")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_event_key:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_event_type(")) {
        if (!hasOptionalImport(&found, "sax_event_type")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_event_type:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_event_current_target(")) {
        if (!hasOptionalImport(&found, "sax_event_current_target")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_event_current_target:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_set_selected(")) {
        if (!hasOptionalImport(&found, "sax_dom_set_selected")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_set_selected:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_get_selected(")) {
        if (!hasOptionalImport(&found, "sax_dom_get_selected")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_get_selected:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_focus(")) {
        if (!hasOptionalImport(&found, "sax_dom_focus")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_focus:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_set_multiple(")) {
        if (!hasOptionalImport(&found, "sax_dom_set_multiple")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_set_multiple:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_get_multiple(")) {
        if (!hasOptionalImport(&found, "sax_dom_get_multiple")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_get_multiple:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_set_disabled(")) {
        if (!hasOptionalImport(&found, "sax_dom_set_disabled")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_set_disabled:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_get_disabled(")) {
        if (!hasOptionalImport(&found, "sax_dom_get_disabled")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_get_disabled:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_set_readonly(")) {
        if (!hasOptionalImport(&found, "sax_dom_set_readonly")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_set_readonly:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_get_readonly(")) {
        if (!hasOptionalImport(&found, "sax_dom_get_readonly")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_get_readonly:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_set_required(")) {
        if (!hasOptionalImport(&found, "sax_dom_set_required")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_set_required:function\n");
            return error.MissingWasmSymbol;
        }
        if (!std.mem.containsAtLeast(u8, airlock, 1, "sax_dom_set_required(node_h, required)")) {
            try std.io.getStdErr().writer().writeAll("airlock.js does not expose sax_dom_set_required for React required props\n");
            return error.InvalidAirlock;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_get_required(")) {
        if (!hasOptionalImport(&found, "sax_dom_get_required")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_get_required:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_set_open(")) {
        if (!hasOptionalImport(&found, "sax_dom_set_open")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_set_open:function\n");
            return error.MissingWasmSymbol;
        }
        if (!std.mem.containsAtLeast(u8, airlock, 1, "sax_dom_set_open(node_h, open)")) {
            try std.io.getStdErr().writer().writeAll("airlock.js does not expose sax_dom_set_open for React open props\n");
            return error.InvalidAirlock;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_get_open(")) {
        if (!hasOptionalImport(&found, "sax_dom_get_open")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_get_open:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_event_prevent_default(")) {
        if (!hasOptionalImport(&found, "sax_event_prevent_default")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_event_prevent_default:function\n");
            return error.MissingWasmSymbol;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_event_stop_propagation(")) {
        if (!hasOptionalImport(&found, "sax_event_stop_propagation")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_event_stop_propagation:function\n");
            return error.MissingWasmSymbol;
        }
    }
    const event_field_checks = [_]struct {
        call: []const u8,
        import_name: []const u8,
        airlock_name: []const u8,
    }{
        .{ .call = "call @sax_event_code(", .import_name = "sax_event_code", .airlock_name = "sax_event_code(buf_ptr, buf_len)" },
        .{ .call = "call @sax_event_target_name(", .import_name = "sax_event_target_name", .airlock_name = "sax_event_target_name(buf_ptr, buf_len)" },
        .{ .call = "call @sax_event_target_id(", .import_name = "sax_event_target_id", .airlock_name = "sax_event_target_id(buf_ptr, buf_len)" },
        .{ .call = "call @sax_event_repeat(", .import_name = "sax_event_repeat", .airlock_name = "sax_event_repeat()" },
        .{ .call = "call @sax_event_data(", .import_name = "sax_event_data", .airlock_name = "sax_event_data(buf_ptr, buf_len)" },
        .{ .call = "call @sax_event_input_type(", .import_name = "sax_event_input_type", .airlock_name = "sax_event_input_type(buf_ptr, buf_len)" },
        .{ .call = "call @sax_event_time_stamp(", .import_name = "sax_event_time_stamp", .airlock_name = "sax_event_time_stamp()" },
        .{ .call = "call @sax_event_current_target_value(", .import_name = "sax_event_current_target_value", .airlock_name = "sax_event_current_target_value(buf_ptr, buf_len)" },
        .{ .call = "call @sax_event_current_target_checked(", .import_name = "sax_event_current_target_checked", .airlock_name = "sax_event_current_target_checked()" },
        .{ .call = "call @sax_event_current_target_name(", .import_name = "sax_event_current_target_name", .airlock_name = "sax_event_current_target_name(buf_ptr, buf_len)" },
        .{ .call = "call @sax_event_current_target_id(", .import_name = "sax_event_current_target_id", .airlock_name = "sax_event_current_target_id(buf_ptr, buf_len)" },
        .{ .call = "call @sax_event_related_target(", .import_name = "sax_event_related_target", .airlock_name = "sax_event_related_target()" },
        .{ .call = "call @sax_event_related_target_name(", .import_name = "sax_event_related_target_name", .airlock_name = "sax_event_related_target_name(buf_ptr, buf_len)" },
        .{ .call = "call @sax_event_related_target_id(", .import_name = "sax_event_related_target_id", .airlock_name = "sax_event_related_target_id(buf_ptr, buf_len)" },
        .{ .call = "call @sax_event_default_prevented(", .import_name = "sax_event_default_prevented", .airlock_name = "sax_event_default_prevented()" },
        .{ .call = "call @sax_event_button(", .import_name = "sax_event_button", .airlock_name = "sax_event_button()" },
        .{ .call = "call @sax_event_client_x(", .import_name = "sax_event_client_x", .airlock_name = "sax_event_client_x()" },
        .{ .call = "call @sax_event_client_y(", .import_name = "sax_event_client_y", .airlock_name = "sax_event_client_y()" },
        .{ .call = "call @sax_event_page_x(", .import_name = "sax_event_page_x", .airlock_name = "sax_event_page_x()" },
        .{ .call = "call @sax_event_page_y(", .import_name = "sax_event_page_y", .airlock_name = "sax_event_page_y()" },
        .{ .call = "call @sax_event_screen_x(", .import_name = "sax_event_screen_x", .airlock_name = "sax_event_screen_x()" },
        .{ .call = "call @sax_event_screen_y(", .import_name = "sax_event_screen_y", .airlock_name = "sax_event_screen_y()" },
        .{ .call = "call @sax_event_pointer_id(", .import_name = "sax_event_pointer_id", .airlock_name = "sax_event_pointer_id()" },
        .{ .call = "call @sax_event_pointer_type(", .import_name = "sax_event_pointer_type", .airlock_name = "sax_event_pointer_type(buf_ptr, buf_len)" },
        .{ .call = "call @sax_event_is_primary(", .import_name = "sax_event_is_primary", .airlock_name = "sax_event_is_primary()" },
        .{ .call = "call @sax_event_delta_x(", .import_name = "sax_event_delta_x", .airlock_name = "sax_event_delta_x()" },
        .{ .call = "call @sax_event_delta_y(", .import_name = "sax_event_delta_y", .airlock_name = "sax_event_delta_y()" },
        .{ .call = "call @sax_event_delta_z(", .import_name = "sax_event_delta_z", .airlock_name = "sax_event_delta_z()" },
        .{ .call = "call @sax_event_delta_mode(", .import_name = "sax_event_delta_mode", .airlock_name = "sax_event_delta_mode()" },
        .{ .call = "call @sax_event_touches_len(", .import_name = "sax_event_touches_len", .airlock_name = "sax_event_touches_len()" },
        .{ .call = "call @sax_event_touch_identifier(", .import_name = "sax_event_touch_identifier", .airlock_name = "sax_event_touch_identifier()" },
        .{ .call = "call @sax_event_touch_client_x(", .import_name = "sax_event_touch_client_x", .airlock_name = "sax_event_touch_client_x()" },
        .{ .call = "call @sax_event_touch_client_y(", .import_name = "sax_event_touch_client_y", .airlock_name = "sax_event_touch_client_y()" },
        .{ .call = "call @sax_event_clipboard_text(", .import_name = "sax_event_clipboard_text", .airlock_name = "sax_event_clipboard_text(buf_ptr, buf_len)" },
        .{ .call = "call @sax_event_data_transfer_text(", .import_name = "sax_event_data_transfer_text", .airlock_name = "sax_event_data_transfer_text(buf_ptr, buf_len)" },
        .{ .call = "call @sax_event_shift_key(", .import_name = "sax_event_shift_key", .airlock_name = "sax_event_shift_key()" },
        .{ .call = "call @sax_event_ctrl_key(", .import_name = "sax_event_ctrl_key", .airlock_name = "sax_event_ctrl_key()" },
        .{ .call = "call @sax_event_alt_key(", .import_name = "sax_event_alt_key", .airlock_name = "sax_event_alt_key()" },
        .{ .call = "call @sax_event_meta_key(", .import_name = "sax_event_meta_key", .airlock_name = "sax_event_meta_key()" },
    };
    for (event_field_checks) |check| {
        if (!std.mem.containsAtLeast(u8, app_sa, 1, check.call)) continue;
        if (!hasOptionalImport(&found, check.import_name)) {
            try std.io.getStdErr().writer().print("missing wasm import env.{s}:function\n", .{check.import_name});
            return error.MissingWasmSymbol;
        }
        if (!std.mem.containsAtLeast(u8, airlock, 1, check.airlock_name)) {
            try std.io.getStdErr().writer().print("airlock.js does not expose {s} for synthetic event fields\n", .{check.import_name});
            return error.InvalidAirlock;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_set_bool_prop(")) {
        if (!hasOptionalImport(&found, "sax_dom_set_bool_prop")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_set_bool_prop:function\n");
            return error.MissingWasmSymbol;
        }
        if (!std.mem.containsAtLeast(u8, airlock, 1, "sax_dom_set_bool_prop(node_h, prop_ptr, prop_len, value)")) {
            try std.io.getStdErr().writer().writeAll("airlock.js does not expose sax_dom_set_bool_prop for React boolean props\n");
            return error.InvalidAirlock;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_get_bool_prop(")) {
        if (!hasOptionalImport(&found, "sax_dom_get_bool_prop")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_get_bool_prop:function\n");
            return error.MissingWasmSymbol;
        }
        if (!std.mem.containsAtLeast(u8, airlock, 1, "sax_dom_get_bool_prop(node_h, prop_ptr, prop_len)")) {
            try std.io.getStdErr().writer().writeAll("airlock.js does not expose sax_dom_get_bool_prop for React boolean props\n");
            return error.InvalidAirlock;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_set_str_prop(")) {
        if (!hasOptionalImport(&found, "sax_dom_set_str_prop")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_set_str_prop:function\n");
            return error.MissingWasmSymbol;
        }
        if (!std.mem.containsAtLeast(u8, airlock, 1, "sax_dom_set_str_prop(node_h, prop_ptr, prop_len, val_ptr, val_len)")) {
            try std.io.getStdErr().writer().writeAll("airlock.js does not expose sax_dom_set_str_prop for React string props\n");
            return error.InvalidAirlock;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_get_str_prop(")) {
        if (!hasOptionalImport(&found, "sax_dom_get_str_prop")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_get_str_prop:function\n");
            return error.MissingWasmSymbol;
        }
        if (!std.mem.containsAtLeast(u8, airlock, 1, "sax_dom_get_str_prop(node_h, prop_ptr, prop_len, buf_ptr, buf_len)")) {
            try std.io.getStdErr().writer().writeAll("airlock.js does not expose sax_dom_get_str_prop for React string props\n");
            return error.InvalidAirlock;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "@extern sax_dom_bind_event")) {
        const forbidden_event_attrs = [_][]const u8{
            "utf8:\"onclick\"",
            "utf8:\"oninput\"",
            "utf8:\"onchange\"",
            "utf8:\"onpointerdown\"",
            "utf8:\"onkeydown\"",
            "utf8:\"onkeyup\"",
            "utf8:\"onclickcapture\"",
            "utf8:\"clickcapture\"",
            "utf8:\"doubleclick\"",
            "utf8:\"doubleclickcapture\"",
            "utf8:\"onmouseenter\"",
            "utf8:\"onmouseleave\"",
            "utf8:\"mouseentercapture\"",
            "utf8:\"mouseleavecapture\"",
        };
        for (forbidden_event_attrs) |needle| {
            if (!std.mem.containsAtLeast(u8, app_sa, 1, needle)) continue;
            try std.io.getStdErr().writer().writeAll("app.sa binds browser events with SAX attribute names instead of DOM event names\n");
            return error.InvalidDemoEventBinding;
        }
    }
    if (std.mem.containsAtLeast(u8, app_sa, 1, "call @sax_dom_bind_event_capture(")) {
        if (!hasOptionalImport(&found, "sax_dom_bind_event_capture")) {
            try std.io.getStdErr().writer().writeAll("missing wasm import env.sax_dom_bind_event_capture:function\n");
            return error.MissingWasmSymbol;
        }
        if (!std.mem.containsAtLeast(u8, airlock, 1, "sax_dom_bind_event_capture(node_h, evt_ptr, evt_len, handler_ptr, handler_len, ctx)")) {
            try std.io.getStdErr().writer().writeAll("airlock.js does not expose sax_dom_bind_event_capture for React capture events\n");
            return error.InvalidAirlock;
        }
    }
}

fn scanWasm(bytes: []const u8, expected_function_exports: []const []const u8, found: *Found) !void {
    if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..4], "\x00asm") or
        !std.mem.eql(u8, bytes[4..8], "\x01\x00\x00\x00"))
    {
        return error.InvalidWasmHeader;
    }

    var index: usize = 8;
    while (index < bytes.len) {
        const section_id = try readByte(bytes, &index);
        const section_size = try readLebU32(bytes, &index);
        const section_end = try checkedSectionEnd(index, section_size, bytes.len);
        const section = bytes[index..section_end];

        switch (section_id) {
            2 => try scanImportSection(section, found),
            7 => try scanExportSection(section, expected_function_exports, found),
            else => {},
        }

        index = section_end;
    }
}

fn scanImportSection(section: []const u8, found: *Found) !void {
    var index: usize = 0;
    const count = try readLebU32(section, &index);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const module = try readName(section, &index);
        const name = try readName(section, &index);
        const kind = try readByte(section, &index);
        for (required_imports, 0..) |symbol, symbol_index| {
            if (symbol.kind == kind and std.mem.eql(u8, symbol.module, module) and std.mem.eql(u8, symbol.name, name)) {
                found.imports[symbol_index] = true;
            }
        }
        for (optional_imports, 0..) |symbol, symbol_index| {
            if (symbol.kind == kind and std.mem.eql(u8, symbol.module, module) and std.mem.eql(u8, symbol.name, name)) {
                found.optional_imports[symbol_index] = true;
            }
        }
        try skipImportDescriptor(section, &index, kind);
    }
    if (index != section.len) return error.InvalidImportSection;
}

fn scanExportSection(section: []const u8, expected_function_exports: []const []const u8, found: *Found) !void {
    var index: usize = 0;
    const count = try readLebU32(section, &index);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const name = try readName(section, &index);
        const kind = try readByte(section, &index);
        _ = try readLebU32(section, &index);
        if (kind == Kind.memory and std.mem.eql(u8, "memory", name)) {
            found.memory_export = true;
            continue;
        }
        if (kind == Kind.function and std.mem.eql(u8, "sax_app_init", name)) {
            found.app_init_export = true;
            continue;
        }
        if (kind == Kind.function) {
            for (expected_function_exports, 0..) |symbol_name, symbol_index| {
                if (std.mem.eql(u8, symbol_name, name)) {
                    found.function_exports[symbol_index] = true;
                }
            }
        }
    }
    if (index != section.len) return error.InvalidExportSection;
}

fn reportMissing(found: *const Found, expected_function_exports: []const []const u8) !void {
    var ok = true;
    const stderr = std.io.getStdErr().writer();
    for (required_imports, 0..) |symbol, index| {
        if (!found.imports[index]) {
            ok = false;
            try stderr.print("missing wasm import {s}.{s}:{s}\n", .{ symbol.module, symbol.name, kindName(symbol.kind) });
        }
    }
    if (!found.memory_export) {
        ok = false;
        try stderr.writeAll("missing wasm export memory:memory\n");
    }
    if (!found.app_init_export) {
        ok = false;
        try stderr.writeAll("missing wasm export sax_app_init:function\n");
    }
    for (expected_function_exports, 0..) |symbol_name, index| {
        if (!found.function_exports[index]) {
            ok = false;
            try stderr.print("missing wasm export {s}:function\n", .{symbol_name});
        }
    }
    if (!ok) return error.MissingWasmSymbol;
}

fn hasOptionalImport(found: *const Found, name: []const u8) bool {
    for (optional_imports, 0..) |symbol, index| {
        if (std.mem.eql(u8, symbol.name, name)) return found.optional_imports[index];
    }
    return false;
}

fn readByte(bytes: []const u8, index: *usize) !u8 {
    if (index.* >= bytes.len) return error.UnexpectedEof;
    const value = bytes[index.*];
    index.* += 1;
    return value;
}

fn readLebU32(bytes: []const u8, index: *usize) !u32 {
    var value: u32 = 0;
    var shift: u6 = 0;
    while (true) {
        if (shift >= 32) return error.InvalidLeb;
        const byte = try readByte(bytes, index);
        const s: u5 = @intCast(shift);
        value |= @as(u32, byte & 0x7f) << s;
        if ((byte & 0x80) == 0) return value;
        shift += 7;
    }
}

fn readName(bytes: []const u8, index: *usize) ![]const u8 {
    const len = try readLebU32(bytes, index);
    const end = try checkedSectionEnd(index.*, len, bytes.len);
    const name = bytes[index.*..end];
    index.* = end;
    return name;
}

fn checkedSectionEnd(start: usize, size: u32, limit: usize) !usize {
    const end = std.math.add(usize, start, @as(usize, size)) catch return error.InvalidSectionSize;
    if (end > limit) return error.UnexpectedEof;
    return end;
}

fn skipImportDescriptor(bytes: []const u8, index: *usize, kind: u8) !void {
    switch (kind) {
        Kind.function => _ = try readLebU32(bytes, index),
        Kind.table => {
            _ = try readByte(bytes, index);
            try skipLimits(bytes, index);
        },
        Kind.memory => try skipLimits(bytes, index),
        Kind.global => {
            _ = try readByte(bytes, index);
            _ = try readByte(bytes, index);
        },
        else => return error.InvalidImportKind,
    }
}

fn skipLimits(bytes: []const u8, index: *usize) !void {
    const flags = try readLebU32(bytes, index);
    _ = try readLebU32(bytes, index);
    if ((flags & 0x01) != 0) _ = try readLebU32(bytes, index);
}

fn kindName(kind: u8) []const u8 {
    return switch (kind) {
        Kind.function => "function",
        Kind.table => "table",
        Kind.memory => "memory",
        Kind.global => "global",
        else => "unknown",
    };
}
