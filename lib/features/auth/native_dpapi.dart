import 'dart:ffi';
import 'dart:typed_data';

import 'auth_failure.dart';
import 'secure_store.dart';

// Windows DPAPI called directly (Crypt32.dll) from the application process: no
// helper program, no console, no standard input to wait for. The optional
// entropy is the same constant the PowerShell implementation uses, so a value
// written by either implementation is readable by the other.

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _CryptNative = Int32 Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Void> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  Uint32 flags,
  Pointer<_DataBlob> dataOut,
);
typedef _CryptDart = int Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Void> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  int flags,
  Pointer<_DataBlob> dataOut,
);
typedef _LocalAllocNative = Pointer<Void> Function(Uint32 flags, IntPtr bytes);
typedef _LocalAllocDart = Pointer<Void> Function(int flags, int bytes);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> memory);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> memory);

/// DPAPI (current-user scope) through `Crypt32.dll`. Synchronous and fast; the
/// calls complete in milliseconds and cannot block on a process or a pipe.
final class NativeDpapiProtector implements DataProtector {
  NativeDpapiProtector() {
    try {
      final crypt = DynamicLibrary.open('crypt32.dll');
      final kernel = DynamicLibrary.open('kernel32.dll');
      _protect = crypt.lookupFunction<_CryptNative, _CryptDart>(
        'CryptProtectData',
      );
      _unprotect = crypt.lookupFunction<_CryptNative, _CryptDart>(
        'CryptUnprotectData',
      );
      _alloc = kernel.lookupFunction<_LocalAllocNative, _LocalAllocDart>(
        'LocalAlloc',
      );
      _free = kernel.lookupFunction<_LocalFreeNative, _LocalFreeDart>(
        'LocalFree',
      );
    } on Object {
      throw const AuthStorageFailure('dpapi_native_unavailable');
    }
  }

  late final _CryptDart _protect;
  late final _CryptDart _unprotect;
  late final _LocalAllocDart _alloc;
  late final _LocalFreeDart _free;

  static const int _uiForbidden = 0x1; // CRYPTPROTECT_UI_FORBIDDEN
  static const int _lptr = 0x40; // LMEM_FIXED | LMEM_ZEROINIT
  static final Uint8List _entropyBytes = Uint8List.fromList(
    'Nexora.Auth.v1'.codeUnits,
  );

  Pointer<Uint8> _copyIn(Uint8List bytes) {
    final memory = _alloc(_lptr, bytes.isEmpty ? 1 : bytes.length);
    if (memory == nullptr) {
      throw const AuthStorageFailure('dpapi_alloc');
    }
    final pointer = memory.cast<Uint8>();
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  Pointer<_DataBlob> _blobFor(Pointer<Uint8> data, int length) {
    final memory = _alloc(_lptr, sizeOf<_DataBlob>());
    if (memory == nullptr) {
      throw const AuthStorageFailure('dpapi_alloc');
    }
    final blob = memory.cast<_DataBlob>();
    blob.ref.cbData = length;
    blob.ref.pbData = data;
    return blob;
  }

  Uint8List _run(_CryptDart function, Uint8List input) {
    final inData = _copyIn(input);
    final entropyData = _copyIn(_entropyBytes);
    final inBlob = _blobFor(inData, input.length);
    final entropyBlob = _blobFor(entropyData, _entropyBytes.length);
    final outBlob = _blobFor(nullptr.cast<Uint8>(), 0);
    try {
      final ok = function(
        inBlob,
        nullptr,
        entropyBlob,
        nullptr,
        nullptr,
        _uiForbidden,
        outBlob,
      );
      if (ok == 0) {
        throw const AuthStorageFailure('dpapi_failed');
      }
      final length = outBlob.ref.cbData;
      final result = Uint8List.fromList(outBlob.ref.pbData.asTypedList(length));
      _free(outBlob.ref.pbData.cast<Void>());
      return result;
    } finally {
      _free(inData.cast<Void>());
      _free(entropyData.cast<Void>());
      _free(inBlob.cast<Void>());
      _free(entropyBlob.cast<Void>());
      _free(outBlob.cast<Void>());
    }
  }

  @override
  Future<Uint8List> protect(Uint8List plain) async => _run(_protect, plain);

  @override
  Future<Uint8List> unprotect(Uint8List blob) async => _run(_unprotect, blob);
}
