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

    pub fn writeString(self: *CustomWriter, str: []const u8) !void {
        try self.writer.writeInt(u16, @intCast(str.len), .big);
        try self.writer.writeAll(str);
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

const ItemAttr = struct {
    attr: u16,
    is_init: bool,

    pub fn encode(self: ItemAttr) ![]u8 {
        var buffer: [3]u8 = undefined;
        var fbs = std.io.fixedBufferStream(buffer[0..]);
        var writer = fbs.writer().any();

        try writer.writeInt(u16, self.attr, .big);
        try writer.writeInt(u8, @intFromBool(self.is_init), .big);

        return fbs.getWritten();
    }
};

const InstAttr = struct {
    id: u16,
    value: u16,

    pub fn encode(self: InstAttr) ![]u8 {
        var buffer: [4]u8 = undefined;
        var fbs = std.io.fixedBufferStream(buffer[0..]);
        var writer = fbs.writer().any();

        try writer.writeInt(u16, self.id, .big);
        try writer.writeInt(u16, self.value, .big);

        return fbs.getWritten();
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

    pub fn encode(self: ItemGrid) ![]u8 {
        var buffer: [1024]u8 = undefined; // Adjust size as needed
        var fbs = std.io.fixedBufferStream(buffer[0..]);
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
            try writer.writeAll(try attr.encode());
        }
        for (self.item_attrs) |attr| {
            try writer.writeAll(try attr.encode());
        }
        try writer.writeInt(u8, @intFromBool(self.is_change), .big);

        return fbs.getWritten();
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
            try writer.writeAll(try grid.encode());
        }
        try writer.writeInt(u16, self.hair, .big);

        return fbs.getWritten();
    }
};

pub const Character = struct {
    is_active: bool,
    name: []const u8,
    job: []const u8,
    level: u16,
    look_size: u16,
    look: Look,

    pub fn encode(self: Character) ![]u8 {
        var buffer: [8192]u8 = undefined; // Adjust size as needed
        var fbs = std.io.fixedBufferStream(buffer[0..]);
        var writer = fbs.writer().any();

        try writer.writeInt(u8, @intFromBool(self.is_active), .big);
        try writer.writeAll(self.name);
        try writer.writeAll(self.job);
        try writer.writeInt(u16, self.level, .big);
        try writer.writeInt(u16, self.look_size, .big);
        try writer.writeAll(try self.look.encode());

        return fbs.getWritten();
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
            return &self.buffer;
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
        try custom_writer.writeString(self.key[0..]);
        try writer.writeInt(u8, self.character_len, .big);
        for (self.characters) |character| {
            try writer.writeAll(try character.encode());
        }
        try writer.writeInt(u8, self.pincode, .big);
        try writer.writeInt(u32, self.encryption, .big);
        try writer.writeInt(u32, self.dw_flag, .big);

        return fbs;
    }
};
