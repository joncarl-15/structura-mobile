import 'dart:typed_data';
import 'package:archive/archive.dart';

abstract class NbtTag {
  dynamic get value;
}

class NbtByte extends NbtTag {
  @override
  final int value;
  NbtByte(this.value);
}

class NbtShort extends NbtTag {
  @override
  final int value;
  NbtShort(this.value);
}

class NbtInt extends NbtTag {
  @override
  final int value;
  NbtInt(this.value);
}

class NbtLong extends NbtTag {
  @override
  final int value;
  NbtLong(this.value);
}

class NbtFloat extends NbtTag {
  @override
  final double value;
  NbtFloat(this.value);
}

class NbtDouble extends NbtTag {
  @override
  final double value;
  NbtDouble(this.value);
}

class NbtString extends NbtTag {
  @override
  final String value;
  NbtString(this.value);
}

class NbtList extends NbtTag {
  @override
  final List<NbtTag> value;
  NbtList(this.value);
}

class NbtCompound extends NbtTag {
  @override
  final Map<String, NbtTag> value;
  NbtCompound(this.value);

  bool containsKey(String key) => value.containsKey(key);
  NbtTag? operator [](String key) => value[key];
  Iterable<String> get keys => value.keys;

  NbtCompound getCompound(String key) {
    if (value[key] is NbtCompound) return value[key] as NbtCompound;
    return NbtCompound({});
  }

  NbtList getList(String key) {
    if (value[key] is NbtList) return value[key] as NbtList;
    return NbtList([]);
  }
}

class NbtReader {
  final ByteData _data;
  int _offset = 0;

  NbtReader(Uint8List bytes)
    : _data = ByteData.sublistView(checkForGzip(bytes));

  static Uint8List checkForGzip(Uint8List bytes) {
    if (bytes.length > 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      return Uint8List.fromList(GZipDecoder().decodeBytes(bytes));
    }
    return bytes;
  }

  NbtTag read() {
    _offset = 0;
    int type = _readByte();
    if (type == 0) return NbtCompound({});

    _readString();

    return _readPayload(type);
  }

  NbtTag _readPayload(int type) {
    switch (type) {
      case 1:
        return NbtByte(_readByte());
      case 2:
        return NbtShort(_readShort());
      case 3:
        return NbtInt(_readInt());
      case 4:
        return NbtLong(_readLong());
      case 5:
        return NbtFloat(_readFloat());
      case 6:
        return NbtDouble(_readDouble());
      case 7: // Byte Array
        int length = _readInt();
        List<NbtTag> bytes = [];
        for (int i = 0; i < length; i++) {
          bytes.add(NbtByte(_readByte()));
        }
        return NbtList(bytes);
      case 8:
        return NbtString(_readString());
      case 9:
        return _readList();
      case 10:
        return _readCompound();
      case 11: // Int Array
        int length = _readInt();
        List<NbtTag> ints = [];
        for (int i = 0; i < length; i++) {
          ints.add(NbtInt(_readInt()));
        }
        return NbtList(ints);
      case 12: // Long Array
        int length = _readInt();
        List<NbtTag> longs = [];
        for (int i = 0; i < length; i++) {
          longs.add(NbtLong(_readLong()));
        }
        return NbtList(longs);
      default:
        return NbtCompound({});
    }
  }

  NbtCompound _readCompound() {
    Map<String, NbtTag> map = {};
    while (true) {
      int type = _readByte();
      if (type == 0) break;
      String name = _readString();
      map[name] = _readPayload(type);
    }
    return NbtCompound(map);
  }

  NbtList _readList() {
    int type = _readByte();
    int length = _readInt();
    List<NbtTag> list = [];
    for (int i = 0; i < length; i++) {
      list.add(_readPayload(type));
    }
    return NbtList(list);
  }

  int _readByte() {
    int val = _data.getInt8(_offset);
    _offset += 1;
    return val;
  }

  int _readShort() {
    int val = _data.getInt16(_offset, Endian.little);
    _offset += 2;
    return val;
  }

  int _readInt() {
    int val = _data.getInt32(_offset, Endian.little);
    _offset += 4;
    return val;
  }

  int _readLong() {
    int val = _data.getInt64(_offset, Endian.little);
    _offset += 8;
    return val;
  }

  double _readFloat() {
    double val = _data.getFloat32(_offset, Endian.little);
    _offset += 4;
    return val;
  }

  double _readDouble() {
    double val = _data.getFloat64(_offset, Endian.little);
    _offset += 8;
    return val;
  }

  String _readString() {
    int length = _data.getUint16(_offset, Endian.little);
    _offset += 2;
    List<int> bytes = [];
    for (int i = 0; i < length; i++) {
      bytes.add(_data.getUint8(_offset));
      _offset++;
    }
    return String.fromCharCodes(bytes);
  }
}
