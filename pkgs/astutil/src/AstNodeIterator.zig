const std = @import("std");
const Ast = std.zig.Ast;

pub const Switch = struct {
    ast: Components,

    pub const Components = struct {
        cond_expr: Ast.Node.Index,
        cases: []const Ast.Node.Index,
    };

    pub fn init(tree: *const Ast, idx: Ast.Node.Index) Switch {
        const data = tree.nodes.items(.data);
        const node_data = data[idx];
        const extra = tree.extraData(node_data.rhs, Ast.Node.SubRange);
        return .{
            .ast = .{
                .cond_expr = node_data.lhs,
                .cases = tree.extra_data[extra.start..extra.end],
            },
        };
    }
};

pub const Block = struct {
    ast: Components,
    pub const Components = struct {
        statements: []const Ast.Node.Index,
    };

    pub fn init(tree: *const Ast, idx: Ast.Node.Index) Block {
        const data = tree.nodes.items(.data);
        const node_data = data[idx];
        const tag = tree.nodes.items(.tag);
        const node_tag = tag[idx];
        return switch (node_tag) {
            .block_two, .block_two_semicolon => Block{
                .ast = .{
                    .statements = @ptrCast([*]const Ast.Node.Index, &data[idx].lhs)[0..2],
                },
            },
            .block, .block_semicolon => Block{
                .ast = .{
                    .statements = tree.extra_data[node_data.lhs..node_data.rhs],
                },
            },
            else => unreachable,
        };
    }
};

pub const BuiltinCall = struct {
    ast: Components,
    pub const Components = struct {
        params: []const Ast.Node.Index,
    };

    pub fn init(tree: *const Ast, idx: Ast.Node.Index) BuiltinCall {
        const data = tree.nodes.items(.data);
        const node_data = data[idx];
        const tag = tree.nodes.items(.tag);
        const node_tag = tag[idx];
        return switch (node_tag) {
            .builtin_call_two, .builtin_call_two_comma => BuiltinCall{
                .ast = .{ .params = if (node_data.lhs == 0)
                    &.{}
                else if (node_data.rhs == 0)
                    @ptrCast([*]const Ast.Node.Index, &data[idx].lhs)[0..1]
                else
                    @ptrCast([*]const Ast.Node.Index, &data[idx].lhs)[0..2] },
            },
            .builtin_call, .builtin_call_comma => BuiltinCall{
                .ast = .{
                    .params = tree.extra_data[node_data.lhs..node_data.rhs],
                },
            },
            else => unreachable,
        };
    }
};

pub const NodeChildren = union(enum) {
    none,
    one: Ast.Node.Index,
    two: Ast.Node.Data,
    nodes: []const Ast.Node.Index,
    var_decl: Ast.full.VarDecl,
    array_type: Ast.full.ArrayType,
    ptr_type: Ast.full.PtrType,
    slice: Ast.full.Slice,
    array_init: Ast.full.ArrayInit,
    struct_init: Ast.full.StructInit,
    call: Ast.full.Call,
    @"switch": Switch,
    switch_case: Ast.full.SwitchCase,
    @"while": Ast.full.While,
    @"if": Ast.full.If,
    fn_proto: Ast.full.FnProto,
    container_decl: Ast.full.ContainerDecl,
    container_field: Ast.full.ContainerField,
    @"asm": Ast.full.Asm,
    block: Block,
    builtin_call: BuiltinCall,

    ///
    /// see: lib/std/zig/Ast.zig Node.Tag
    ///
    pub fn init(
        tree: *const Ast,
        idx: Ast.Node.Index,
        buffer: []Ast.Node.Index,
    ) NodeChildren {
        std.debug.assert(idx < tree.nodes.len);
        std.debug.assert(buffer.len >= 2);
        const tag = tree.nodes.items(.tag);
        const node_tag = tag[idx];
        const data = tree.nodes.items(.data);
        const node_data = data[idx];

        return switch (node_tag) {
            .root => .{ .container_decl = tree.containerDeclRoot() },
            .@"usingnamespace" => .{ .one = node_data.lhs },
            .test_decl => .{ .one = node_data.rhs },
            .global_var_decl => .{ .var_decl = tree.globalVarDecl(idx) },
            .local_var_decl => .{ .var_decl = tree.localVarDecl(idx) },
            .simple_var_decl => .{ .var_decl = tree.simpleVarDecl(idx) },
            .aligned_var_decl => .{ .var_decl = tree.alignedVarDecl(idx) },
            .@"errdefer" => .{ .two = node_data },
            .@"defer" => .{ .one = node_data.rhs },
            .@"catch" => .{ .two = node_data },
            .field_access => .{ .one = node_data.lhs },
            .unwrap_optional => .{ .one = node_data.lhs },
            // == != < > <= >=
            .equal_equal, .bang_equal, .less_than, .greater_than, .less_or_equal, .greater_or_equal => .{ .two = node_data },
            // *= /= %= += -=
            .assign_mul, .assign_div, .assign_mod, .assign_add, .assign_sub => .{ .two = node_data },
            // <<= <<|= >>= &= ^= |=
            .assign_shl, .assign_shl_sat, .assign_shr, .assign_bit_and, .assign_bit_xor, .assign_bit_or => .{ .two = node_data },
            // *%= +%= -%=
            .assign_mul_wrap, .assign_add_wrap, .assign_sub_wrap => .{ .two = node_data },
            // *|= +|= -|= = ||
            .assign_mul_sat, .assign_add_sat, .assign_sub_sat, .assign, .merge_error_sets => .{ .two = node_data },
            // * /  % ** *% *|
            .mul, .div, .mod, .array_mult, .mul_wrap, .mul_sat => .{ .two = node_data },
            // + - ++ +% -% +| -|
            .add, .sub, .array_cat, .add_wrap, .sub_wrap, .add_sat, .sub_sat => .{ .two = node_data },
            // << <<| >> & ^ |
            .shl, .shl_sat, .shr, .bit_and, .bit_xor, .bit_or => .{ .two = node_data },
            // orelse and or
            .@"orelse", .bool_and, .bool_or => .{ .two = node_data },
            // ! - &
            .bool_not, .negation, .bit_not, .negation_wrap, .address_of => .{ .one = node_data.lhs },
            // try await ?
            .@"try", .@"await", .optional_type => .{ .one = node_data.lhs },
            .array_type => .{ .array_type = tree.arrayType(idx) },
            .array_type_sentinel => .{ .array_type = tree.arrayTypeSentinel(idx) },
            .ptr_type_aligned => .{ .ptr_type = tree.ptrTypeAligned(idx) },
            .ptr_type_sentinel => .{ .ptr_type = tree.ptrTypeSentinel(idx) },
            .ptr_type => .{ .ptr_type = tree.ptrType(idx) },
            .ptr_type_bit_range => .{ .ptr_type = tree.ptrTypeBitRange(idx) },
            .slice_open => .{ .slice = tree.sliceOpen(idx) },
            .slice => .{ .slice = tree.slice(idx) },
            .slice_sentinel => .{ .slice = tree.sliceSentinel(idx) },
            .deref => .{ .one = node_data.lhs },
            .array_access => .{ .two = node_data },
            .array_init_one, .array_init_one_comma => .{ .array_init = tree.arrayInitOne(buffer[0..1], idx) },
            .array_init_dot_two, .array_init_dot_two_comma => .{ .array_init = tree.arrayInitDotTwo(buffer[0..2], idx) },
            .array_init_dot, .array_init_dot_comma => .{ .array_init = tree.arrayInitDot(idx) },
            .array_init, .array_init_comma => .{ .array_init = tree.arrayInit(idx) },
            .struct_init_one, .struct_init_one_comma => .{ .struct_init = tree.structInitOne(buffer[0..1], idx) },
            .struct_init_dot_two, .struct_init_dot_two_comma => .{ .struct_init = tree.structInitDotTwo(buffer[0..2], idx) },
            .struct_init_dot, .struct_init_dot_comma => .{ .struct_init = tree.structInitDot(idx) },
            .struct_init, .struct_init_comma => .{ .struct_init = tree.structInit(idx) },
            .call_one, .call_one_comma, .async_call_one, .async_call_one_comma => .{ .call = tree.callOne(buffer[0..1], idx) },
            .call, .call_comma, .async_call, .async_call_comma => .{ .call = tree.callFull(idx) },
            .@"switch", .switch_comma => .{ .@"switch" = Switch.init(tree, idx) },
            .switch_case_one => .{ .switch_case = tree.switchCaseOne(idx) },
            .switch_case => .{ .switch_case = tree.switchCase(idx) },
            .switch_range => .{ .two = node_data },
            .while_simple => .{ .@"while" = tree.whileSimple(idx) },
            .while_cont => .{ .@"while" = tree.whileCont(idx) },
            .@"while" => .{ .@"while" = tree.whileFull(idx) },
            .for_simple => .{ .@"while" = tree.forSimple(idx) },
            .@"for" => .{ .@"while" = tree.forFull(idx) },
            .if_simple => .{ .@"if" = tree.ifSimple(idx) },
            .@"if" => .{ .@"if" = tree.ifFull(idx) },
            .@"suspend" => .{ .one = node_data.lhs },
            .@"resume" => .{ .one = node_data.lhs },
            .@"continue" => .none,
            .@"break" => .{ .one = node_data.rhs },
            .@"return" => .{ .one = node_data.lhs },
            .fn_proto_simple => .{ .fn_proto = tree.fnProtoSimple(buffer[0..1], idx) },
            .fn_proto_multi => .{ .fn_proto = tree.fnProtoMulti(idx) },
            .fn_proto_one => .{ .fn_proto = tree.fnProtoOne(buffer[0..1], idx) },
            .fn_proto => .{ .fn_proto = tree.fnProto(idx) },
            .fn_decl => .{ .two = node_data },
            .anyframe_type => .{ .one = node_data.rhs },
            .anyframe_literal, .char_literal, .integer_literal, .float_literal, .unreachable_literal, .identifier, .enum_literal, .string_literal, .multiline_string_literal => .none,
            .grouped_expression => .{ .one = node_data.lhs },
            .builtin_call_two, .builtin_call_two_comma, .builtin_call, .builtin_call_comma => .{ .builtin_call = BuiltinCall.init(tree, idx) },
            .error_set_decl => .none,
            .container_decl, .container_decl_trailing => .{ .container_decl = tree.containerDecl(idx) },
            .container_decl_two, .container_decl_two_trailing => .{ .container_decl = tree.containerDeclTwo(buffer[0..2], idx) },
            .container_decl_arg, .container_decl_arg_trailing => .{ .container_decl = tree.containerDeclArg(idx) },
            .tagged_union, .tagged_union_trailing => .{ .container_decl = tree.taggedUnion(idx) },
            .tagged_union_two, .tagged_union_two_trailing => .{ .container_decl = tree.taggedUnionTwo(buffer[0..2], idx) },
            .tagged_union_enum_tag, .tagged_union_enum_tag_trailing => .{ .container_decl = tree.taggedUnionEnumTag(idx) },
            .container_field_init => .{ .container_field = tree.containerFieldInit(idx) },
            .container_field_align => .{ .container_field = tree.containerFieldAlign(idx) },
            .container_field => .{ .container_field = tree.containerField(idx) },
            .@"comptime" => .{ .one = node_data.lhs },
            .@"nosuspend" => .{ .one = node_data.lhs },
            .block_two, .block_two_semicolon, .block, .block_semicolon => .{ .block = Block.init(tree, idx) },
            .asm_simple => .{ .@"asm" = tree.asmSimple(idx) },
            .@"asm" => .{ .@"asm" = tree.asmFull(idx) },
            .asm_output, .asm_input, .error_value => .none,
            .error_union => .{ .two = node_data },
        };
    }

    pub fn debugPrint(self: NodeChildren, w: anytype) !void {
        try w.print("\n* NodeChildren: {s}\n\n", .{@tagName(self)});
        switch (self) {
            .none => {},
            .one => {},
            .two => {},
            .nodes => {},
            .var_decl => {},
            .array_type => {},
            .ptr_type => {},
            .slice => {},
            .array_init => {},
            .struct_init => {},
            .call => {},
            .@"switch" => {},
            .switch_case => {},
            .@"while" => {},
            .@"if" => {},
            .fn_proto => {},
            .container_decl => {},
            .container_field => {},
            .@"asm" => {},
            .block => {},
            .builtin_call => {},
        }
    }
};

const Self = @This();

frame: anyframe->void = undefined,
value: ?Ast.Node.Index = null,
idx: Ast.Node.Index,
buffer: [2]u32 = undefined,

pub fn init(idx: Ast.Node.Index) Self {
    return Self{ .idx = idx };
}

pub fn next(self: *Self) void {
    resume self.frame;
}

pub fn iterateAsync(self: *Self, tree: *const Ast) void {
    switch (NodeChildren.init(tree, self.idx, &self.buffer)) {
        .none => {},
        .one => |single| {
            self.setIfNotZero(single);
        },
        .two => |lr| {
            self.setIfNotZero(lr.lhs);
            self.setIfNotZero(lr.rhs);
        },
        .nodes => |nodes| {
            for (nodes) |node| {
                self.setIfNotZero(node);
            }
        },
        .var_decl => |value| self.addChildren(Ast.full.VarDecl.Components, value.ast),
        .array_type => |value| self.addChildren(Ast.full.ArrayType.Components, value.ast),
        .ptr_type => |value| self.addChildren(Ast.full.PtrType.Components, value.ast),
        .slice => |value| self.addChildren(Ast.full.Slice.Components, value.ast),
        .array_init => |value| self.addChildren(Ast.full.ArrayInit.Components, value.ast),
        .struct_init => |value| self.addChildren(Ast.full.StructInit.Components, value.ast),
        .call => |value| self.addChildren(Ast.full.Call.Components, value.ast),
        .@"switch" => |value| self.addChildren(Switch.Components, value.ast),
        .switch_case => |value| self.addChildren(Ast.full.SwitchCase.Components, value.ast),
        .@"while" => |value| self.addChildren(Ast.full.While.Components, value.ast),
        .@"if" => |value| self.addChildren(Ast.full.If.Components, value.ast),
        .fn_proto => |value| self.addChildren(Ast.full.FnProto.Components, value.ast),
        .container_decl => |value| self.addChildren(Ast.full.ContainerDecl.Components, value.ast),
        .container_field => |value| self.addChildren(Ast.full.ContainerField.Components, value.ast),
        .@"asm" => |value| self.addChildren(Ast.full.Asm.Components, value.ast),
        .block => |value| self.addChildren(Block.Components, value.ast),
        .builtin_call => |value| self.addChildren(BuiltinCall.Components, value.ast),
    }
    self.value = null;
}

fn setIfNotZero(self: *Self, value: Ast.Node.Index) void {
    if (value == 0) {
        // invalid value
        return;
    }
    if (value == self.idx) {
        // avoid infinite loop
        return;
    }
    self.value = value;
    suspend {
        self.frame = @frame();
    }
}

fn addChildren(self: *Self, comptime T: type, t: T) void {
    const info = @typeInfo(T);
    switch (info) {
        .Struct => |s| {
            inline for (s.fields) |field| {
                if (field.field_type == Ast.Node.Index) {
                    if (!std.mem.endsWith(u8, field.name, "_token") and !std.mem.endsWith(u8, field.name, "paren") and !std.mem.endsWith(u8, field.name, "brace") and !std.mem.endsWith(u8, field.name, "bracket")) {
                        self.setIfNotZero(@field(t, field.name));
                    }
                } else if (field.field_type == []const Ast.Node.Index) {
                    for (@field(t, field.name)) |value| {
                        self.setIfNotZero(value);
                    }
                }
            }
        },
        else => {
            unreachable;
        },
    }
}
