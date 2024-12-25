const std = @import("std");

pub const Opcode = enum(u16) {
    auth = 431,
    exit = 432,
    response_chars = 931,
    first_date = 940,
    create_pincode = 346,
    create_pincode_reply = 941,
    create_character = 435,
    create_character_reply = 935,
    remove_character = 436,
    remove_character_reply = 936,
    update_pincode = 347,
    update_pincode_reply = 942,
};

pub const Header = struct {
    size: u16,
    id: u32,
    opcode: u16,
    data: []const u8,
};

pub fn unpack(buf: []const u8) !Header {
    var fbs = std.io.fixedBufferStream(buf);
    const size = try fbs.reader().readInt(u16, .big);
    const id = try fbs.reader().readInt(u32, .little);
    const opcode = try fbs.reader().readInt(u16, .big);

    return Header{ .size = size, .id = id, .opcode = opcode, .data = buf[8..size] };
}

pub fn pack(opcode: u16, data: []const u8) ![]u8 {
    var buf: [8096]u8 = undefined;

    var fbs = std.io.fixedBufferStream(&buf);
    var writer = fbs.writer();

    try writer.writeInt(u16, @intCast(data.len + 8), .big);
    try writer.writeInt(u32, 128, .little);
    try writer.writeInt(u16, opcode, .big);
    try writer.writeAll(data);

    return buf[0..fbs.pos];
}

pub const FirstTime = struct {
    data: []const u8 = "[01-01 13:05:35:333]",

    pub fn encode(self: FirstTime) ![]u8 {
        var buf: [128]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        var writer = fbs.writer();

        try writer.writeAll(self.data);

        return buf[0..fbs.pos];
    }
};

pub const CustomWriter = struct {
    writer: std.io.AnyWriter,

    pub fn writeAll(self: *CustomWriter, bytes: []const u8) !void {
        try self.writer.writeAll(bytes);
    }

    pub fn writeString(self: *CustomWriter, str: CompositeString) !void {
        try self.writer.writeInt(u16, @intCast(str.len), .big);
        try self.writer.writeAll(str.get());
    }

    pub fn writeBytes(self: *CustomWriter, bytes: []const u8) !void {
        try self.writer.writeInt(u16, @intCast(bytes.len), .big);
        try self.writer.writeAll(bytes);
    }

    pub fn writeFixedBuffer(self: *CustomWriter, comptime size: usize, fbs: fixedBuffer(size)) !void {
        var encoded = fbs;
        std.debug.print("Encoded {any}\n", .{encoded.getWritten().len});
        try self.writer.writeAll(encoded.getWritten());
    }
};

pub const CompositeString = struct {
    str: [256]u8,
    len: u16,

    pub fn get(self: CompositeString) []const u8 {
        return self.str[0..self.len];
    }
};

const CustomReader = struct {
    reader: *std.io.AnyReader,

    pub fn readString(self: *CustomReader) !CompositeString {
        var str: [256]u8 = undefined;

        const len = try self.reader.readInt(u16, .big);
        _ = try self.reader.readAll(str[0..len]);

        return CompositeString{ .str = str, .len = len };
    }
};

pub const Auth = struct {
    key: CompositeString,
    login: CompositeString,
    password: CompositeString,
    mac: CompositeString,
    is_cheat: u16,
    client_version: u16,

    pub fn decode(data: []const u8) !Auth {
        std.debug.print("Auth {any}\n", .{data});

        var fbs = std.io.fixedBufferStream(data);
        var reader = fbs.reader().any();
        var custom_reader = CustomReader{ .reader = &reader };

        const key = try custom_reader.readString();

        std.debug.print("Key {any}\n", .{key});
        const login = try custom_reader.readString();
        const password = try custom_reader.readString();
        const mac = try custom_reader.readString();
        const is_cheat = try reader.readInt(u16, .big);
        const client_version = try reader.readInt(u16, .big);

        return Auth{
            .key = key,
            .login = login,
            .password = password,
            .mac = mac,
            .is_cheat = is_cheat,
            .client_version = client_version,
        };
    }
};

fn intToBool(value: anytype) bool {
    return if (value == 1) true else false;
}

const ItemAttr = struct {
    attr: u16,
    is_init: bool,

    pub fn encode(self: ItemAttr) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();

        try writer.writeInt(u16, self.attr, .big);
        try writer.writeInt(u8, @intFromBool(self.is_init), .big);

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !ItemAttr {
        var reader = fbs.reader().any();

        const attr = try reader.readInt(u16, .big);
        const is_init = try reader.readInt(u8, .big);
        const is_init_bool = intToBool(is_init);

        return ItemAttr{
            .attr = attr,
            .is_init = is_init_bool,
        };
    }
};

const InstAttr = struct {
    id: u16,
    value: u16,

    pub fn encode(self: InstAttr) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();

        try writer.writeInt(u16, self.id, .big);
        try writer.writeInt(u16, self.value, .big);

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !InstAttr {
        var reader = fbs.reader().any();

        const id = try reader.readInt(u16, .big);
        const value = try reader.readInt(u16, .big);

        return InstAttr{
            .id = id,
            .value = value,
        };
    }
};

const ItemGrid = struct {
    id: u16,
    num: u16,
    endure: [2]u16,
    energy: [2]u16,
    forge_lv: u8,
    db_params: [2]u32,
    inst_attrs: [5]InstAttr,
    item_attrs: [40]ItemAttr,
    is_change: bool,

    pub fn encode(self: ItemGrid) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();

        try writer.writeInt(u16, self.id, .big);
        try writer.writeInt(u16, self.num, .big);
        for (self.endure) |e| {
            try writer.writeInt(u16, e, .big);
        }
        for (self.energy) |e| {
            try writer.writeInt(u16, e, .big);
        }
        try writer.writeInt(u8, self.forge_lv, .big);
        for (self.db_params) |p| {
            try writer.writeInt(u32, p, .big);
        }
        for (self.inst_attrs) |attr| {
            var encoded = try attr.encode();
            try writer.writeAll(encoded.getWritten());
        }
        for (self.item_attrs) |attr| {
            var encoded = try attr.encode();
            try writer.writeAll(encoded.getWritten());
        }
        try writer.writeInt(u8, @intFromBool(self.is_change), .big);

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !ItemGrid {
        var reader = fbs.reader().any();

        const id = try reader.readInt(u16, .big);
        const num = try reader.readInt(u16, .big);

        var endure: [2]u16 = undefined;
        for (0..2) |i| {
            endure[i] = try reader.readInt(u16, .big);
        }

        var energy: [2]u16 = undefined;
        for (0..2) |i| {
            energy[i] = try reader.readInt(u16, .big);
        }

        const forge_lv = try reader.readInt(u8, .big);

        var db_params: [2]u32 = undefined;
        for (0..2) |i| {
            db_params[i] = try reader.readInt(u32, .big);
        }

        var inst_attrs: [5]InstAttr = undefined;
        for (0..5) |i| {
            inst_attrs[i] = try InstAttr.decode(fbs);
        }

        var item_attrs: [40]ItemAttr = undefined;
        for (0..40) |i| {
            item_attrs[i] = try ItemAttr.decode(fbs);
        }

        const is_change = try reader.readInt(u8, .big) != 0;

        return ItemGrid{
            .id = id,
            .num = num,
            .endure = endure,
            .energy = energy,
            .forge_lv = forge_lv,
            .db_params = db_params,
            .inst_attrs = inst_attrs,
            .item_attrs = item_attrs,
            .is_change = is_change,
        };
    }
};

const Look = struct {
    ver: u16,
    type_id: u16,
    item_grids: [10]ItemGrid,
    hair: u16,

    pub fn encode(self: Look) ![]u8 {
        var buffer: [4096]u8 = undefined; // Adjust size as needed
        var fbs = std.io.fixedBufferStream(buffer[0..]);
        var writer = fbs.writer().any();

        try writer.writeInt(u16, self.ver, .big);
        try writer.writeInt(u16, self.type_id, .big);
        for (self.item_grids) |grid| {
            var encoded = try grid.encode();
            try writer.writeAll(encoded.getWritten());
        }
        try writer.writeInt(u16, self.hair, .big);

        return fbs.getWritten();
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !Look {
        var reader = fbs.reader().any();

        const ver = try reader.readInt(u16, .big);
        const type_id = try reader.readInt(u16, .big);

        var item_grids: [10]ItemGrid = undefined;
        for (0..10) |i| {
            item_grids[i] = try ItemGrid.decode(fbs);
        }

        const hair = try reader.readInt(u16, .big);

        return Look{
            .ver = ver,
            .type_id = type_id,
            .item_grids = item_grids,
            .hair = hair,
        };
    }
};

pub const Character = struct {
    is_active: bool,
    name: []const u8,
    job: []const u8,
    level: u16,
    look_size: u16,
    look: Look,

    pub fn encode(self: Character) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();

        try writer.writeInt(u8, @intFromBool(self.is_active), .big);
        try writer.writeAll(self.name);
        try writer.writeAll(self.job);
        try writer.writeInt(u16, self.level, .big);
        try writer.writeInt(u16, self.look_size, .big);
        try writer.writeAll(try self.look.encode());

        return fbs;
    }
};

pub fn fixedBuffer(comptime size: usize) type {
    return struct {
        buffer: [size]u8 = undefined,
        len: usize = 0,

        const Self = @This();

        pub fn init() Self {
            return .{};
        }

        pub fn writer(self: *Self) std.io.Writer(*Self, error{NoSpaceLeft}, write) {
            return .{ .context = self };
        }

        pub fn write(self: *Self, data: []const u8) error{NoSpaceLeft}!usize {
            if (self.len + data.len > size) return error.NoSpaceLeft;
            @memcpy(self.buffer[self.len..][0..data.len], data);
            self.len += data.len;

            return data.len;
        }

        pub fn getWritten(self: *Self) []const u8 {
            return self.buffer[0..self.len];
        }
    };
}

pub const CharacterScreen = struct {
    error_code: u16,
    key: [8]u8 = [_]u8{ 0x7C, 0x35, 0x09, 0x19, 0xB2, 0x50, 0xD3, 0x49 },
    character_len: u8,
    characters: []Character,
    pincode: u8,
    encryption: u32,
    dw_flag: u32 = 12820,

    pub fn encode(self: CharacterScreen) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try writer.writeInt(u16, self.error_code, .big);
        try custom_writer.writeBytes(self.key[0..]);
        try writer.writeInt(u8, self.character_len, .big);
        for (self.characters) |character| {
            var char_encode = try character.encode();
            try writer.writeAll(char_encode.getWritten());
        }
        try writer.writeInt(u8, self.pincode, .big);
        try writer.writeInt(u32, self.encryption, .big);
        try writer.writeInt(u32, self.dw_flag, .big);

        return fbs;
    }
};

pub const CharacterCreate = struct {
    name: CompositeString,
    map: CompositeString,
    look_size: u16,
    look: Look,

    pub fn encode(self: CharacterCreate) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try custom_writer.writeString(self.name);
        try custom_writer.writeString(self.map);
        try writer.writeInt(u16, self.look_size, .big);
        try writer.writeAll(try self.look.encode());

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !CharacterCreate {
        var reader = fbs.reader().any();
        var custom_reader = CustomReader{ .reader = &reader };

        const name = try custom_reader.readString();
        const map = try custom_reader.readString();
        const look_size = try reader.readInt(u16, .big);
        const look = try Look.decode(fbs);

        return CharacterCreate{ .name = name, .map = map, .look_size = look_size, .look = look };
    }
};

pub const CharacterCreateReply = struct {
    error_code: u16,

    pub fn init() CharacterCreateReply {
        return CharacterCreateReply{ .error_code = 0x0000 };
    }

    pub fn encode(self: CharacterCreateReply) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();

        try writer.writeInt(u16, self.error_code, .big);

        return fbs;
    }
};

pub const CharacterRemove = struct {
    name: CompositeString,
    hash: CompositeString,

    pub fn encode(self: CharacterRemove) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        const writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try custom_writer.writeString(self.name);
        try custom_writer.writeString(self.hash);

        return fbs;
    }

    pub fn decode(data: []const u8) !CharacterRemove {
        const reader = std.io.fixedBufferStream(data).reader();
        var custom_reader = CustomReader{ .reader = reader };

        const name = try custom_reader.readString();
        const hash = try custom_reader.readString();

        return CharacterRemove{ .name = name, .hash = hash };
    }
};

pub const CharacterRemoveReply = struct {
    error_code: u16,

    pub fn init() CharacterRemoveReply {
        return CharacterRemoveReply{ .error_code = 0x0000 };
    }

    pub fn encode(self: CharacterRemoveReply) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();

        try writer.writeInt(u16, self.error_code, .big);

        return fbs;
    }
};

pub const CreatePincode = struct {
    hash: CompositeString,

    pub fn init(hash: []const u8) CreatePincode {
        return CreatePincode{ .hash = hash };
    }

    pub fn encode(self: CreatePincode) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        const writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try custom_writer.writeString(self.hash);

        return fbs;
    }

    pub fn decode(data: []const u8) !CreatePincode {
        const reader = std.io.fixedBufferStream(data).reader();
        var custom_reader = CustomReader{ .reader = reader };

        const hash = try custom_reader.readString();

        return CreatePincode{ .hash = hash };
    }
};

pub const CreatePincodeReply = struct {
    error_code: u16,

    pub fn init() CreatePincodeReply {
        return CreatePincodeReply{ .error_code = 0x0000 };
    }

    pub fn encode(self: CreatePincodeReply) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();

        try writer.writeInt(u16, self.error_code, .big);

        return fbs;
    }
};

pub const UpdatePincode = struct {
    old_hash: CompositeString,
    hash: CompositeString,

    pub fn encode(self: UpdatePincode) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        const writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try custom_writer.writeString(self.old_hash);
        try custom_writer.writeString(self.hash);

        return fbs;
    }

    pub fn decode(data: []const u8) !UpdatePincode {
        const reader = std.io.fixedBufferStream(data).reader();
        var custom_reader = CustomReader{ .reader = reader };

        const old_hash = try custom_reader.readString();
        const hash = try custom_reader.readString();

        return UpdatePincode{
            .old_hash = old_hash,
            .hash = hash,
        };
    }
};

pub const UpdatePincodeReply = struct {
    error_code: u16,

    pub fn init() UpdatePincodeReply {
        return UpdatePincodeReply{ .error_code = 0x0000 };
    }

    pub fn encode(self: UpdatePincodeReply) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();

        try writer.writeInt(u16, self.error_code, .big);

        return fbs;
    }
};

pub const Shortcut = struct {
    type: u8,
    grid_id: u16,

    pub fn encode(self: Shortcut) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer();

        try writer.writeInt(u8, self.type, .big);
        try writer.writeInt(u16, self.grid_id, .big);

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !Shortcut {
        var reader = fbs.reader().any();

        const type_val = try reader.readInt(u8, .big);
        const grid_id = try reader.readInt(u16, .big);

        return Shortcut{
            .type = type_val,
            .grid_id = grid_id,
        };
    }
};

pub const CharacterShortcut = struct {
    shortcuts: [36]Shortcut,

    pub fn init() CharacterShortcut {
        var shortcuts: [36]Shortcut = undefined;
        for (0..36) |i| {
            shortcuts[i] = Shortcut{ .type = 0, .grid_id = 0 };
        }
        return CharacterShortcut{ .shortcuts = shortcuts };
    }

    pub fn encode(self: CharacterShortcut) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        const writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        for (self.shortcuts) |shortcut| {
            try custom_writer.writeFixedBuffer(1024, try shortcut.encode());
        }

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !CharacterShortcut {
        var shortcuts: [36]Shortcut = undefined;
        for (0..36) |i| {
            shortcuts[i] = try Shortcut.decode(fbs);
        }

        return CharacterShortcut{ .shortcuts = shortcuts };
    }
};

pub const KitbagItem = struct {
    grid_id: u16,
    id: u16,
    num: u16,
    endure: [2]u16,
    energy: [2]u16,
    forge_level: u8,
    is_valid: bool,
    item_db_inst_id: u32,
    item_db_forge: u32,
    boat_null: u32,
    item_db_inst_id2: u32,
    is_params: bool,
    inst_attrs: [5]InstAttr,

    pub fn encode(self: KitbagItem) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try writer.writeInt(u16, self.grid_id, .big);
        try writer.writeInt(u16, self.id, .big);
        try writer.writeInt(u16, self.num, .big);
        for (self.endure) |e| {
            try writer.writeInt(u16, e, .big);
        }
        for (self.energy) |e| {
            try writer.writeInt(u16, e, .big);
        }
        try writer.writeInt(u8, self.forge_level, .big);
        try writer.writeInt(u8, @intFromBool(self.is_valid), .big);
        try writer.writeInt(u32, self.item_db_inst_id, .big);
        try writer.writeInt(u32, self.item_db_forge, .big);
        try writer.writeInt(u32, self.boat_null, .big);
        try writer.writeInt(u32, self.item_db_inst_id2, .big);
        try writer.writeInt(u8, @intFromBool(self.is_params), .big);
        for (self.inst_attrs) |attr| {
            try custom_writer.writeFixedBuffer(1024, try attr.encode());
        }

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !KitbagItem {
        var reader = fbs.reader().any();

        const grid_id = try reader.readInt(u16, .big);
        const id = try reader.readInt(u16, .big);
        const num = try reader.readInt(u16, .big);

        var endure: [2]u16 = undefined;
        for (0..2) |i| {
            endure[i] = try reader.readInt(u16, .big);
        }

        var energy: [2]u16 = undefined;
        for (0..2) |i| {
            energy[i] = try reader.readInt(u16, .big);
        }

        const forge_level = try reader.readInt(u8, .big);
        const is_valid = (try reader.readInt(u8, .big)) != 0;
        const item_db_inst_id = try reader.readInt(u32, .big);
        const item_db_forge = try reader.readInt(u32, .big);
        const boat_null = try reader.readInt(u32, .big);
        const item_db_inst_id2 = try reader.readInt(u32, .big);
        const is_params = (try reader.readInt(u8, .big)) != 0;

        var inst_attrs: [5]InstAttr = undefined;
        for (0..5) |i| {
            inst_attrs[i] = try InstAttr.decode(fbs);
        }

        return KitbagItem{
            .grid_id = grid_id,
            .id = id,
            .num = num,
            .endure = endure,
            .energy = energy,
            .forge_level = forge_level,
            .is_valid = is_valid,
            .item_db_inst_id = item_db_inst_id,
            .item_db_forge = item_db_forge,
            .boat_null = boat_null,
            .item_db_inst_id2 = item_db_inst_id2,
            .is_params = is_params,
            .inst_attrs = inst_attrs,
        };
    }
};

pub const CharacterKitbag = struct {
    type: u8,
    keybag_num: u16,
    items: std.ArrayList(KitbagItem),

    pub fn init(allocator: std.mem.Allocator) CharacterKitbag {
        return CharacterKitbag{
            .type = 0,
            .keybag_num = 0,
            .items = std.ArrayList(KitbagItem).init(allocator),
        };
    }

    pub fn deinit(self: *CharacterKitbag) void {
        self.items.deinit();
    }

    pub fn encode(self: CharacterKitbag) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try writer.writeInt(u8, self.type, .big);
        try writer.writeInt(u16, self.keybag_num, .big);
        try writer.writeInt(u16, @intCast(self.items.items.len), .big);

        for (self.items.items) |item| {
            try custom_writer.writeFixedBuffer(1024, try item.encode());
        }

        return fbs;
    }

    pub fn decode(allocator: std.mem.Allocator, fbs: *std.io.FixedBufferStream([]const u8)) !CharacterKitbag {
        var reader = fbs.reader().any();

        const type_val = try reader.readInt(u8, .big);
        const keybag_num = try reader.readInt(u16, .big);
        const items_len = try reader.readInt(u16, .big);

        var items = std.ArrayList(KitbagItem).init(allocator);
        errdefer items.deinit();

        var i: usize = 0;
        while (i < items_len) : (i += 1) {
            const item = try KitbagItem.decode(fbs);
            try items.append(item);
        }

        return CharacterKitbag{
            .type = type_val,
            .keybag_num = keybag_num,
            .items = items,
        };
    }
};

pub const CharacterAppendLook = struct {
    look_id: u16,
    is_valid: u8,

    pub fn encode(self: CharacterAppendLook) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();

        try writer.writeInt(u16, self.look_id, .big);
        try writer.writeInt(u8, self.is_valid, .big);

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !CharacterAppendLook {
        var reader = fbs.reader().any();

        const look_id = try reader.readInt(u16, .big);
        const is_valid = try reader.readInt(u8, .big);

        return CharacterAppendLook{
            .look_id = look_id,
            .is_valid = is_valid,
        };
    }
};

pub const CharacterPK = struct {
    pk_ctrl: u8,

    pub fn init() CharacterPK {
        return CharacterPK{
            .pk_ctrl = 0,
        };
    }

    pub fn encode(self: CharacterPK) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();

        try writer.writeInt(u8, self.pk_ctrl, .big);

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !CharacterPK {
        var reader = fbs.reader().any();

        const pk_ctrl = try reader.readInt(u8, .big);

        return CharacterPK{
            .pk_ctrl = pk_ctrl,
        };
    }
};

pub const CharacterLookBoat = struct {
    pos_id: u16,
    boat_id: u16,
    header: u16,
    body: u16,
    engine: u16,
    cannon: u16,
    equipment: u16,

    pub fn init() CharacterLookBoat {
        return CharacterLookBoat{
            .pos_id = 0,
            .boat_id = 0,
            .header = 0,
            .body = 0,
            .engine = 0,
            .cannon = 0,
            .equipment = 0,
        };
    }

    pub fn encode(self: CharacterLookBoat) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();

        try writer.writeInt(u16, self.pos_id, .big);
        try writer.writeInt(u16, self.boat_id, .big);
        try writer.writeInt(u16, self.header, .big);
        try writer.writeInt(u16, self.body, .big);
        try writer.writeInt(u16, self.engine, .big);
        try writer.writeInt(u16, self.cannon, .big);
        try writer.writeInt(u16, self.equipment, .big);

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !CharacterLookBoat {
        var reader = fbs.reader().any();

        const pos_id = try reader.readInt(u16, .big);
        const boat_id = try reader.readInt(u16, .big);
        const header = try reader.readInt(u16, .big);
        const body = try reader.readInt(u16, .big);
        const engine = try reader.readInt(u16, .big);
        const cannon = try reader.readInt(u16, .big);
        const equipment = try reader.readInt(u16, .big);

        return CharacterLookBoat{
            .pos_id = pos_id,
            .boat_id = boat_id,
            .header = header,
            .body = body,
            .engine = engine,
            .cannon = cannon,
            .equipment = equipment,
        };
    }
};

pub const CharacterLookItemSync = struct {
    endure: u16,
    energy: u16,
    is_valid: u8,

    pub fn encode(self: CharacterLookItemSync) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();

        try writer.writeInt(u16, self.endure, .big);
        try writer.writeInt(u16, self.energy, .big);
        try writer.writeInt(u8, self.is_valid, .big);

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !CharacterLookItemSync {
        var reader = fbs.reader().any();

        const endure = try reader.readInt(u16, .big);
        const energy = try reader.readInt(u16, .big);
        const is_valid = try reader.readInt(u8, .big);

        return CharacterLookItemSync{
            .endure = endure,
            .energy = energy,
            .is_valid = is_valid,
        };
    }
};

pub const CharacterLookItemShow = struct {
    num: u16,
    endure: [2]u16,
    energy: [2]u16,
    forge_level: u8,
    is_valid: u8,

    pub fn encode(self: CharacterLookItemShow) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();

        try writer.writeInt(u16, self.num, .big);
        for (self.endure) |e| {
            try writer.writeInt(u16, e, .big);
        }
        for (self.energy) |e| {
            try writer.writeInt(u16, e, .big);
        }
        try writer.writeInt(u8, self.forge_level, .big);
        try writer.writeInt(u8, self.is_valid, .big);

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !CharacterLookItemShow {
        var reader = fbs.reader().any();

        const num = try reader.readInt(u16, .big);
        var endure: [2]u16 = undefined;
        for (0..2) |i| {
            endure[i] = try reader.readInt(u16, .big);
        }
        var energy: [2]u16 = undefined;
        for (0..2) |i| {
            energy[i] = try reader.readInt(u16, .big);
        }
        const forge_level = try reader.readInt(u8, .big);
        const is_valid = try reader.readInt(u8, .big);

        return CharacterLookItemShow{
            .num = num,
            .endure = endure,
            .energy = energy,
            .forge_level = forge_level,
            .is_valid = is_valid,
        };
    }
};

pub const CharacterLookItem = struct {
    syn_type: u8,
    id: u16,
    item_sync: CharacterLookItemSync,
    item_show: CharacterLookItemShow,
    is_db_params: u8,
    db_params: [2]u32,
    is_inst_attrs: u8,
    inst_attrs: [5]InstAttr,

    pub fn init() CharacterLookItem {
        return CharacterLookItem{
            .syn_type = 0,
            .id = 0,
            .item_sync = CharacterLookItemSync{ .endure = 0, .energy = 0, .is_valid = 0 },
            .item_show = CharacterLookItemShow{
                .num = 0,
                .endure = [_]u16{0} ** 2,
                .energy = [_]u16{0} ** 2,
                .forge_level = 0,
                .is_valid = 0,
            },
            .is_db_params = 0,
            .db_params = [_]u32{0} ** 2,
            .is_inst_attrs = 0,
            .inst_attrs = [_]InstAttr{InstAttr{ .id = 0, .value = 0 }} ** 5,
        };
    }

    pub fn encode(self: CharacterLookItem) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try writer.writeInt(u8, self.syn_type, .big);
        try writer.writeInt(u16, self.id, .big);
        try custom_writer.writeFixedBuffer(1024, try self.item_sync.encode());
        try custom_writer.writeFixedBuffer(1024, try self.item_show.encode());
        try writer.writeInt(u8, self.is_db_params, .big);
        for (self.db_params) |param| {
            try writer.writeInt(u32, param, .big);
        }
        try writer.writeInt(u8, self.is_inst_attrs, .big);
        for (self.inst_attrs) |attr| {
            try custom_writer.writeFixedBuffer(1024, try attr.encode());
        }

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !CharacterLookItem {
        var reader = fbs.reader().any();

        const syn_type = try reader.readInt(u8, .big);
        const id = try reader.readInt(u16, .big);
        const item_sync = try CharacterLookItemSync.decode(fbs);
        const item_show = try CharacterLookItemShow.decode(fbs);
        const is_db_params = try reader.readInt(u8, .big);

        var db_params: [2]u32 = undefined;
        for (0..2) |i| {
            db_params[i] = try reader.readInt(u32, .big);
        }

        const is_inst_attrs = try reader.readInt(u8, .big);
        var inst_attrs: [5]InstAttr = undefined;
        for (0..5) |i| {
            inst_attrs[i] = try InstAttr.decode(fbs);
        }

        return CharacterLookItem{
            .syn_type = syn_type,
            .id = id,
            .item_sync = item_sync,
            .item_show = item_show,
            .is_db_params = is_db_params,
            .db_params = db_params,
            .is_inst_attrs = is_inst_attrs,
            .inst_attrs = inst_attrs,
        };
    }
};

pub const CharacterLookHuman = struct {
    hair_id: u16,
    item_grid: [10]CharacterLookItem,

    pub fn init() CharacterLookHuman {
        return CharacterLookHuman{
            .hair_id = 2817,
            .item_grid = [_]CharacterLookItem{CharacterLookItem.init()} ** 10,
        };
    }

    pub fn encode(self: CharacterLookHuman) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try writer.writeInt(u16, self.hair_id, .big);
        for (self.item_grid) |item| {
            try custom_writer.writeFixedBuffer(1024, try item.encode());
        }

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !CharacterLookHuman {
        var reader = fbs.reader().any();

        const hair_id = try reader.readInt(u16, .big);
        var item_grid: [10]CharacterLookItem = undefined;
        for (0..10) |i| {
            item_grid[i] = try CharacterLookItem.decode(fbs);
        }

        return CharacterLookHuman{
            .hair_id = hair_id,
            .item_grid = item_grid,
        };
    }
};

pub const CharacterLook = struct {
    syn_type: u8,
    type_id: u16,
    is_boat: u8,
    look_boat: CharacterLookBoat,
    look_human: CharacterLookHuman,

    pub fn init() CharacterLook {
        return CharacterLook{
            .syn_type = 0,
            .type_id = 4,
            .is_boat = 0,
            .look_boat = CharacterLookBoat.init(),
            .look_human = CharacterLookHuman.init(),
        };
    }

    pub fn encode(self: CharacterLook) !fixedBuffer(4096) {
        var fbs = fixedBuffer(4096).init();
        var writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try writer.writeInt(u8, self.syn_type, .big);
        try writer.writeInt(u16, self.type_id, .big);
        try writer.writeInt(u8, self.is_boat, .big);
        try custom_writer.writeFixedBuffer(1024, try self.look_boat.encode());
        try custom_writer.writeFixedBuffer(1024, try self.look_human.encode());

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !CharacterLook {
        var reader = fbs.reader().any();

        const syn_type = try reader.readInt(u8, .big);
        const type_id = try reader.readInt(u16, .big);
        const is_boat = try reader.readInt(u8, .big);
        const look_boat = try CharacterLookBoat.decode(fbs);
        const look_human = try CharacterLookHuman.decode(fbs);

        return CharacterLook{
            .syn_type = syn_type,
            .type_id = type_id,
            .is_boat = is_boat,
            .look_boat = look_boat,
            .look_human = look_human,
        };
    }
};

pub const EntityEvent = struct {
    entity_id: u32,
    entity_type: u8,
    event_id: u16,
    event_name: CompositeString,

    pub fn encode(self: EntityEvent) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try writer.writeInt(u32, self.entity_id, .big);
        try writer.writeInt(u8, self.entity_type, .big);
        try writer.writeInt(u16, self.event_id, .big);
        try custom_writer.writeString(self.event_name);

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !EntityEvent {
        var reader = fbs.reader().any();
        var custom_reader = CustomReader{ .reader = &reader };

        const entity_id = try reader.readInt(u32, .big);
        const entity_type = try reader.readInt(u8, .big);
        const event_id = try reader.readInt(u16, .big);
        const event_name = try custom_reader.readString();

        return EntityEvent{
            .entity_id = entity_id,
            .entity_type = entity_type,
            .event_id = event_id,
            .event_name = event_name,
        };
    }
};

pub const CharacterSide = struct {
    side_id: u8,

    pub fn init() CharacterSide {
        return CharacterSide{
            .side_id = 0,
        };
    }

    pub fn encode(self: CharacterSide) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();

        try writer.writeInt(u8, self.side_id, .big);

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !CharacterSide {
        var reader = fbs.reader().any();

        const side_id = try reader.readInt(u8, .big);

        return CharacterSide{
            .side_id = side_id,
        };
    }
};

pub const Position = struct {
    x: u32,
    y: u32,
    radius: u32,

    pub fn encode(self: Position) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();

        try writer.writeInt(u32, self.x, .big);
        try writer.writeInt(u32, self.y, .big);
        try writer.writeInt(u32, self.radius, .big);

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !Position {
        var reader = fbs.reader().any();

        const x = try reader.readInt(u32, .big);
        const y = try reader.readInt(u32, .big);
        const radius = try reader.readInt(u32, .big);

        return Position{
            .x = x,
            .y = y,
            .radius = radius,
        };
    }
};

pub const CharacterBase = struct {
    cha_id: u32,
    world_id: u32,
    comm_id: u32,
    comm_name: CompositeString,
    gm_lvl: u8,
    handle: u32,
    ctrl_type: u8,
    name: CompositeString,
    motto_name: CompositeString,
    icon: u16,
    guild_id: u32,
    guild_name: CompositeString,
    guild_motto: CompositeString,
    stall_name: CompositeString,
    state: u16,
    position: Position,
    angle: u16,
    team_leader_id: u32,
    side: CharacterSide,
    entity_event: EntityEvent,
    look: CharacterLook,
    pk_ctrl: CharacterPK,
    look_append: [4]CharacterAppendLook,

    pub fn init() CharacterBase {
        return CharacterBase{
            .cha_id = 240,
            .world_id = 212,
            .comm_id = 1,
            .comm_name = CompositeString{ .str = undefined, .len = 0 },
            .gm_lvl = 0,
            .handle = 0,
            .ctrl_type = 0,
            .name = CompositeString{ .str = undefined, .len = 0 },
            .motto_name = CompositeString{ .str = undefined, .len = 0 },
            .icon = 0,
            .guild_id = 0,
            .guild_name = CompositeString{ .str = undefined, .len = 0 },
            .guild_motto = CompositeString{ .str = undefined, .len = 0 },
            .stall_name = CompositeString{ .str = undefined, .len = 0 },
            .state = 0,
            .position = Position{ .x = 0, .y = 0, .radius = 0 },
            .angle = 0,
            .team_leader_id = 0,
            .side = CharacterSide.init(),
            .entity_event = EntityEvent{
                .entity_id = 0,
                .entity_type = 0,
                .event_id = 0,
                .event_name = CompositeString{ .str = undefined, .len = 0 },
            },
            .look = CharacterLook.init(),
            .pk_ctrl = CharacterPK.init(),
            .look_append = [_]CharacterAppendLook{
                CharacterAppendLook{ .look_id = 0, .is_valid = 0 },
                CharacterAppendLook{ .look_id = 0, .is_valid = 0 },
                CharacterAppendLook{ .look_id = 0, .is_valid = 0 },
                CharacterAppendLook{ .look_id = 0, .is_valid = 0 },
            },
        };
    }

    pub fn encode(self: CharacterBase) !fixedBuffer(65535) {
        var fbs = fixedBuffer(65535).init();
        var writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try writer.writeInt(u32, self.cha_id, .big);
        try writer.writeInt(u32, self.world_id, .big);
        try writer.writeInt(u32, self.comm_id, .big);
        try custom_writer.writeString(self.comm_name);
        try writer.writeInt(u8, self.gm_lvl, .big);
        try writer.writeInt(u32, self.handle, .big);
        try writer.writeInt(u8, self.ctrl_type, .big);
        try custom_writer.writeString(self.name);
        try custom_writer.writeString(self.motto_name);
        try writer.writeInt(u16, self.icon, .big);
        try writer.writeInt(u32, self.guild_id, .big);
        try custom_writer.writeString(self.guild_name);
        try custom_writer.writeString(self.guild_motto);
        try custom_writer.writeString(self.stall_name);
        try writer.writeInt(u16, self.state, .big);
        try custom_writer.writeFixedBuffer(1024, try self.position.encode());
        try writer.writeInt(u16, self.angle, .big);
        try writer.writeInt(u32, self.team_leader_id, .big);
        try custom_writer.writeFixedBuffer(1024, try self.side.encode());
        try custom_writer.writeFixedBuffer(1024, try self.entity_event.encode());
        try custom_writer.writeFixedBuffer(4096, try self.look.encode());
        try custom_writer.writeFixedBuffer(1024, try self.pk_ctrl.encode());
        for (self.look_append) |append| {
            try custom_writer.writeFixedBuffer(1024, try append.encode());
        }

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !CharacterBase {
        var reader = fbs.reader().any();
        var custom_reader = CustomReader{ .reader = &reader };

        const cha_id = try reader.readInt(u32, .big);
        const world_id = try reader.readInt(u32, .big);
        const comm_id = try reader.readInt(u32, .big);
        const comm_name = try custom_reader.readString();
        const gm_lvl = try reader.readInt(u8, .big);
        const handle = try reader.readInt(u32, .big);
        const ctrl_type = try reader.readInt(u8, .big);
        const name = try custom_reader.readString();
        const motto_name = try custom_reader.readString();
        const icon = try reader.readInt(u16, .big);
        const guild_id = try reader.readInt(u32, .big);
        const guild_name = try custom_reader.readString();
        const guild_motto = try custom_reader.readString();
        const stall_name = try custom_reader.readString();
        const state = try reader.readInt(u16, .big);
        const position = try Position.decode(fbs);
        const angle = try reader.readInt(u16, .big);
        const team_leader_id = try reader.readInt(u32, .big);
        const side = try CharacterSide.decode(fbs);
        const entity_event = try EntityEvent.decode(fbs);
        const look = try CharacterLook.decode(fbs);
        const pk_ctrl = try CharacterPK.decode(fbs);

        var look_append: [4]CharacterAppendLook = undefined;
        for (0..4) |i| {
            look_append[i] = try CharacterAppendLook.decode(fbs);
        }

        return CharacterBase{
            .cha_id = cha_id,
            .world_id = world_id,
            .comm_id = comm_id,
            .comm_name = comm_name,
            .gm_lvl = gm_lvl,
            .handle = handle,
            .ctrl_type = ctrl_type,
            .name = name,
            .motto_name = motto_name,
            .icon = icon,
            .guild_id = guild_id,
            .guild_name = guild_name,
            .guild_motto = guild_motto,
            .stall_name = stall_name,
            .state = state,
            .position = position,
            .angle = angle,
            .team_leader_id = team_leader_id,
            .side = side,
            .entity_event = entity_event,
            .look = look,
            .pk_ctrl = pk_ctrl,
            .look_append = look_append,
        };
    }
};

pub const CharacterBoat = struct {
    character_base: CharacterBase,
    character_attribute: CharacterAttribute,
    character_kitbag: CharacterKitbag,
    character_skill_state: CharacterSkillState,

    pub fn init(allocator: std.mem.Allocator) CharacterBoat {
        return CharacterBoat{
            .character_base = CharacterBase.init(),
            .character_attribute = CharacterAttribute.init(allocator),
            .character_kitbag = CharacterKitbag.init(allocator),
            .character_skill_state = CharacterSkillState.init(allocator),
        };
    }

    pub fn deinit(self: *CharacterBoat) void {
        self.character_attribute.deinit();
        self.character_kitbag.deinit();
        self.character_skill_state.deinit();
    }

    pub fn encode(self: CharacterBoat) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        const writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try custom_writer.writeFixedBuffer(65535, try self.character_base.encode());
        try custom_writer.writeFixedBuffer(1024, try self.character_attribute.encode());
        try custom_writer.writeFixedBuffer(1024, try self.character_kitbag.encode());
        try custom_writer.writeFixedBuffer(1024, try self.character_skill_state.encode());

        return fbs;
    }

    pub fn decode(allocator: std.mem.Allocator, fbs: *std.io.FixedBufferStream([]const u8)) !CharacterBoat {
        const character_base = try CharacterBase.decode(fbs);
        const character_attribute = try CharacterAttribute.decode(allocator, fbs);
        const character_kitbag = try CharacterKitbag.decode(allocator, fbs);
        const character_skill_state = try CharacterSkillState.decode(allocator, fbs);

        return CharacterBoat{
            .character_base = character_base,
            .character_attribute = character_attribute,
            .character_kitbag = character_kitbag,
            .character_skill_state = character_skill_state,
        };
    }
};

pub const EnterGame = struct {
    enter_ret: u16,
    auto_lock: u8,
    kitbag_lock: u8,
    enter_type: u8,
    is_new_char: u8,
    map_name: CompositeString,
    can_team: u8,
    character_base: CharacterBase,
    character_skill_bag: CharacterSkillBag,
    character_skill_state: CharacterSkillState,
    character_attribute: CharacterAttribute,
    character_kitbag: CharacterKitbag,
    character_shortcut: CharacterShortcut,
    boat_len: u8,
    character_boats: std.ArrayList(CharacterBoat),
    cha_main_id: u32,

    pub fn init(allocator: std.mem.Allocator) EnterGame {
        return EnterGame{
            .enter_ret = 1,
            .auto_lock = 1,
            .kitbag_lock = 1,
            .enter_type = 1,
            .is_new_char = 1,
            .map_name = CompositeString{ .str = undefined, .len = 0 },
            .can_team = 1,
            .character_base = CharacterBase.init(),
            .character_skill_bag = CharacterSkillBag.init(allocator),
            .character_skill_state = CharacterSkillState.init(allocator),
            .character_attribute = CharacterAttribute.init(allocator),
            .character_kitbag = CharacterKitbag.init(allocator),
            .character_shortcut = CharacterShortcut.init(),
            .boat_len = 0,
            .character_boats = std.ArrayList(CharacterBoat).init(allocator),
            .cha_main_id = 240,
        };
    }

    pub fn deinit(self: *EnterGame) void {
        self.character_skill_bag.deinit();
        self.character_skill_state.deinit();
        self.character_attribute.deinit();
        self.character_kitbag.deinit();
        for (self.character_boats.items) |*boat| {
            boat.deinit();
        }
        self.character_boats.deinit();
    }

    pub fn encode(self: EnterGame) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        var writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try writer.writeInt(u16, self.enter_ret, .big);
        try writer.writeInt(u8, self.auto_lock, .big);
        try writer.writeInt(u8, self.kitbag_lock, .big);
        try writer.writeInt(u8, self.enter_type, .big);
        try writer.writeInt(u8, self.is_new_char, .big);
        try custom_writer.writeString(self.map_name);
        try writer.writeInt(u8, self.can_team, .big);
        try custom_writer.writeFixedBuffer(65535, try self.character_base.encode());
        try custom_writer.writeFixedBuffer(1024, try self.character_skill_bag.encode());
        try custom_writer.writeFixedBuffer(1024, try self.character_skill_state.encode());
        try custom_writer.writeFixedBuffer(1024, try self.character_attribute.encode());
        try custom_writer.writeFixedBuffer(1024, try self.character_kitbag.encode());
        try custom_writer.writeFixedBuffer(1024, try self.character_shortcut.encode());
        try writer.writeInt(u8, self.boat_len, .big);
        try writer.writeInt(u16, @intCast(self.character_boats.items.len), .big);

        for (self.character_boats.items) |boat| {
            try custom_writer.writeFixedBuffer(1024, try boat.encode());
        }

        try writer.writeInt(u32, self.cha_main_id, .big);

        std.debug.print("Encoded {any}\n", .{fbs.getWritten()});

        return fbs;
    }

    pub fn decode(allocator: std.mem.Allocator, fbs: *std.io.FixedBufferStream([]const u8)) !EnterGame {
        var reader = fbs.reader().any();
        var custom_reader = CustomReader{ .reader = &reader };

        const enter_ret = try reader.readInt(u16, .big);
        const auto_lock = try reader.readInt(u8, .big);
        const kitbag_lock = try reader.readInt(u8, .big);
        const enter_type = try reader.readInt(u8, .big);
        const is_new_char = try reader.readInt(u8, .big);
        const map_name = try custom_reader.readString();
        const can_team = try reader.readInt(u8, .big);
        const character_base = try CharacterBase.decode(fbs);
        const character_skill_bag = try CharacterSkillBag.decode(allocator, fbs);
        const character_skill_state = try CharacterSkillState.decode(allocator, fbs);
        const character_attribute = try CharacterAttribute.decode(allocator, fbs);
        const character_kitbag = try CharacterKitbag.decode(allocator, fbs);
        const character_shortcut = try CharacterShortcut.decode(fbs);
        const boat_len = try reader.readInt(u8, .big);
        const boats_len = try reader.readInt(u16, .big);

        var character_boats = std.ArrayList(CharacterBoat).init(allocator);
        errdefer {
            for (character_boats.items) |*boat| {
                boat.deinit();
            }
            character_boats.deinit();
        }

        for (0..boats_len) |_| {
            const boat = try CharacterBoat.decode(allocator, fbs);
            try character_boats.append(boat);
        }

        const cha_main_id = try reader.readInt(u32, .big);

        return EnterGame{
            .enter_ret = enter_ret,
            .auto_lock = auto_lock,
            .kitbag_lock = kitbag_lock,
            .enter_type = enter_type,
            .is_new_char = is_new_char,
            .map_name = map_name,
            .can_team = can_team,
            .character_base = character_base,
            .character_skill_bag = character_skill_bag,
            .character_skill_state = character_skill_state,
            .character_attribute = character_attribute,
            .character_kitbag = character_kitbag,
            .character_shortcut = character_shortcut,
            .boat_len = boat_len,
            .character_boats = character_boats,
            .cha_main_id = cha_main_id,
        };
    }
};

pub const EnterGameRequest = struct {
    character_name: CompositeString,

    pub fn encode(self: EnterGameRequest) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        const writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try custom_writer.writeString(self.character_name);

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !EnterGameRequest {
        var reader = fbs.reader().any();
        var custom_reader = CustomReader{ .reader = &reader };

        const character_name = try custom_reader.readString();

        return EnterGameRequest{
            .character_name = character_name,
        };
    }
};

pub const Attribute = struct {
    id: u8,
    value: u32,

    pub fn encode(self: Attribute) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        const writer = fbs.writer().any();

        try writer.writeInt(u8, self.id, .big);
        try writer.writeInt(u32, self.value, .big);

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !Attribute {
        var reader = fbs.reader().any();

        const id = try reader.readInt(u8, .big);
        const value = try reader.readInt(u32, .big);

        return Attribute{
            .id = id,
            .value = value,
        };
    }
};

pub const CharacterAttribute = struct {
    type: u8,
    num: u16,
    attributes: std.ArrayList(Attribute),

    pub fn init(allocator: std.mem.Allocator) CharacterAttribute {
        return CharacterAttribute{
            .type = 0,
            .num = 0,
            .attributes = std.ArrayList(Attribute).init(allocator),
        };
    }

    pub fn deinit(self: *CharacterAttribute) void {
        self.attributes.deinit();
    }

    pub fn encode(self: CharacterAttribute) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        const writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try writer.writeInt(u8, self.type, .big);
        try writer.writeInt(u16, self.num, .big);
        try writer.writeInt(u16, @intCast(self.attributes.items.len), .big);

        for (self.attributes.items) |attr| {
            try custom_writer.writeFixedBuffer(1024, try attr.encode());
        }

        return fbs;
    }

    pub fn decode(allocator: std.mem.Allocator, fbs: *std.io.FixedBufferStream([]const u8)) !CharacterAttribute {
        var reader = fbs.reader().any();

        const type_val = try reader.readInt(u8, .big);
        const num = try reader.readInt(u16, .big);
        const attrs_len = try reader.readInt(u16, .big);

        var attributes = std.ArrayList(Attribute).init(allocator);
        errdefer attributes.deinit();

        var i: usize = 0;
        while (i < attrs_len) : (i += 1) {
            const attr = try Attribute.decode(fbs);
            try attributes.append(attr);
        }

        return CharacterAttribute{
            .type = type_val,
            .num = num,
            .attributes = attributes,
        };
    }
};

pub const SkillState = struct {
    id: u8,
    level: u8,

    pub fn encode(self: SkillState) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        const writer = fbs.writer().any();

        try writer.writeInt(u8, self.id, .big);
        try writer.writeInt(u8, self.level, .big);

        return fbs;
    }

    pub fn decode(fbs: *std.io.FixedBufferStream([]const u8)) !SkillState {
        var reader = fbs.reader().any();

        const id = try reader.readInt(u8, .big);
        const level = try reader.readInt(u8, .big);

        return SkillState{
            .id = id,
            .level = level,
        };
    }
};

pub const CharacterSkillState = struct {
    states_len: u8,
    states: std.ArrayList(SkillState),

    pub fn init(allocator: std.mem.Allocator) CharacterSkillState {
        return CharacterSkillState{
            .states_len = 0,
            .states = std.ArrayList(SkillState).init(allocator),
        };
    }

    pub fn deinit(self: *CharacterSkillState) void {
        self.states.deinit();
    }

    pub fn encode(self: CharacterSkillState) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        const writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try writer.writeInt(u8, self.states_len, .big);
        try writer.writeInt(u16, @intCast(self.states.items.len), .big);

        for (self.states.items) |state| {
            try custom_writer.writeFixedBuffer(1024, try state.encode());
        }

        return fbs;
    }

    pub fn decode(allocator: std.mem.Allocator, fbs: *std.io.FixedBufferStream([]const u8)) !CharacterSkillState {
        var reader = fbs.reader().any();

        const states_len = try reader.readInt(u8, .big);
        const states_count = try reader.readInt(u16, .big);

        var states = std.ArrayList(SkillState).init(allocator);
        errdefer states.deinit();

        var i: usize = 0;
        while (i < states_count) : (i += 1) {
            const state = try SkillState.decode(fbs);
            try states.append(state);
        }

        return CharacterSkillState{
            .states_len = states_len,
            .states = states,
        };
    }
};

pub const CharacterSkill = struct {
    id: u16,
    state: u8,
    level: u8,
    use_sp: u16,
    use_endure: u16,
    use_energy: u16,
    resume_time: u32,
    range_type: u16,
    params: std.ArrayList(u16),

    pub fn init(allocator: std.mem.Allocator) CharacterSkill {
        return CharacterSkill{
            .id = 0,
            .state = 0,
            .level = 0,
            .use_sp = 0,
            .use_endure = 0,
            .use_energy = 0,
            .resume_time = 0,
            .range_type = 0,
            .params = std.ArrayList(u16).init(allocator),
        };
    }

    pub fn deinit(self: *CharacterSkill) void {
        self.params.deinit();
    }

    pub fn encode(self: CharacterSkill) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        const writer = fbs.writer().any();

        try writer.writeInt(u16, self.id, .big);
        try writer.writeInt(u8, self.state, .big);
        try writer.writeInt(u8, self.level, .big);
        try writer.writeInt(u16, self.use_sp, .big);
        try writer.writeInt(u16, self.use_endure, .big);
        try writer.writeInt(u16, self.use_energy, .big);
        try writer.writeInt(u32, self.resume_time, .big);
        try writer.writeInt(u16, self.range_type, .big);
        try writer.writeInt(u16, @intCast(self.params.items.len), .big);

        for (self.params.items) |param| {
            try writer.writeInt(u16, param, .big);
        }

        return fbs;
    }

    pub fn decode(allocator: std.mem.Allocator, fbs: *std.io.FixedBufferStream([]const u8)) !CharacterSkill {
        var reader = fbs.reader().any();

        const id = try reader.readInt(u16, .big);
        const state = try reader.readInt(u8, .big);
        const level = try reader.readInt(u8, .big);
        const use_sp = try reader.readInt(u16, .big);
        const use_endure = try reader.readInt(u16, .big);
        const use_energy = try reader.readInt(u16, .big);
        const resume_time = try reader.readInt(u32, .big);
        const range_type = try reader.readInt(u16, .big);
        const params_len = try reader.readInt(u16, .big);

        var params = std.ArrayList(u16).init(allocator);
        errdefer params.deinit();

        var i: usize = 0;
        while (i < params_len) : (i += 1) {
            const param = try reader.readInt(u16, .big);
            try params.append(param);
        }

        return CharacterSkill{
            .id = id,
            .state = state,
            .level = level,
            .use_sp = use_sp,
            .use_endure = use_endure,
            .use_energy = use_energy,
            .resume_time = resume_time,
            .range_type = range_type,
            .params = params,
        };
    }
};

pub const CharacterSkillBag = struct {
    skill_id: u16,
    type: u8,
    skill_num: u16,
    skills: std.ArrayList(CharacterSkill),

    pub fn init(allocator: std.mem.Allocator) CharacterSkillBag {
        return CharacterSkillBag{
            .skill_id = 0,
            .type = 0,
            .skill_num = 0,
            .skills = std.ArrayList(CharacterSkill).init(allocator),
        };
    }

    pub fn deinit(self: *CharacterSkillBag) void {
        for (self.skills.items) |*skill| {
            skill.deinit();
        }
        self.skills.deinit();
    }

    pub fn encode(self: CharacterSkillBag) !fixedBuffer(1024) {
        var fbs = fixedBuffer(1024).init();
        const writer = fbs.writer().any();
        var custom_writer = CustomWriter{ .writer = writer };

        try writer.writeInt(u16, self.skill_id, .big);
        try writer.writeInt(u8, self.type, .big);
        try writer.writeInt(u16, self.skill_num, .big);
        try writer.writeInt(u16, @intCast(self.skills.items.len), .big);

        for (self.skills.items) |skill| {
            try custom_writer.writeFixedBuffer(1024, try skill.encode());
        }

        return fbs;
    }

    pub fn decode(allocator: std.mem.Allocator, fbs: *std.io.FixedBufferStream([]const u8)) !CharacterSkillBag {
        var reader = fbs.reader().any();

        const skill_id = try reader.readInt(u16, .big);
        const type_val = try reader.readInt(u8, .big);
        const skill_num = try reader.readInt(u16, .big);
        const skills_len = try reader.readInt(u16, .big);

        var skills = std.ArrayList(CharacterSkill).init(allocator);
        errdefer {
            for (skills.items) |*skill| {
                skill.deinit();
            }
            skills.deinit();
        }

        var i: usize = 0;
        while (i < skills_len) : (i += 1) {
            const skill = try CharacterSkill.decode(allocator, fbs);
            try skills.append(skill);
        }

        return CharacterSkillBag{
            .skill_id = skill_id,
            .type = type_val,
            .skill_num = skill_num,
            .skills = skills,
        };
    }
};

test "EnterGame" {
    const enter_game = EnterGame.init(std.testing.allocator);
    var buffer = try enter_game.encode();
    std.debug.print("Encoded {any}\n", .{buffer.getWritten()});

    const buf_slice: []const u8 = buffer.getWritten();
    var fbs = std.io.fixedBufferStream(buf_slice);
    const decoded = try EnterGame.decode(std.testing.allocator, &fbs);

    std.debug.print("Decoded {any}\n", .{decoded});
}
