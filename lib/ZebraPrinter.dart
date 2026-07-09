import 'dart:io';

import 'package:flutter/services.dart';

enum EnumMediaType { Label, BlackMark, Journal, Barcode }

enum Command { calibrate, mediaType, darkness }

class ZebraPrinter {
  late MethodChannel channel;

  Function? onPrinterFound;
  Function? onPrinterDiscoveryDone;
  Function? onDiscoveryError;
  Function? onChangePrinterStatus;
  Function? onPermissionDenied;

  bool isRotated = false;

  ZebraPrinter(String id, this.onPrinterFound, this.onPrinterDiscoveryDone,
      this.onDiscoveryError, this.onChangePrinterStatus,
      {this.onPermissionDenied}) {
    channel = MethodChannel('ZebraPrinterObject' + id);
    channel.setMethodCallHandler(nativeMethodCallHandler);
  }

  discoveryPrinters() {
    channel.invokeMethod("checkPermission").then((isGrantPermission) {
      if (isGrantPermission)
        channel.invokeMethod("discoverPrinters");
      else {
        if (onPermissionDenied != null) onPermissionDenied!();
      }
    });
  }

  Future<void> _setSettings(Command setting, dynamic values) async {
    String command = "";
    switch (setting) {
      case Command.mediaType:
        if (values == EnumMediaType.BlackMark) {
          command = '''
          ! U1 setvar "media.type" "label"
          ! U1 setvar "media.sense_mode" "bar"
          ''';
        } else if (values == EnumMediaType.Journal) {
          command = '''
          ! U1 setvar "media.type" "journal"
          ! U1 setvar "device.languages" "line_print"
          ''';
        } else if (values == EnumMediaType.Barcode) {
          command = '''
          ! U1 setvar "media.type" "journal"
          ! U1 setvar "media.sense_mode" "continuous"
          ! U1 setvar "device.languages" "zpl"
          ~JC^XA^JUS^XZ
          ''';
        } else if (values == EnumMediaType.Label) {
          command = '''
          ! U1 setvar "media.type" "label"
          ! U1 setvar "media.sense_mode" "gap"
          ''';
        }
        break;
      case Command.calibrate:
        command = '''~jc^xa^jus^xz''';
        break;
      case Command.darkness:
        command = '''! U1 setvar "print.tone" "$values"''';
        break;
    }

    if (setting == Command.calibrate) {
      command = '''~jc^xa^jus^xz''';
    }

    try {
      await channel.invokeMethod("setSettings", {"SettingCommand": command});
    } on PlatformException catch (e) {}
  }

  Future<void> setDarkness(int darkness) {
    return _setSettings(Command.darkness, darkness.toString());
  }

  Future<void> setMediaType(EnumMediaType mediaType) {
    return _setSettings(Command.mediaType, mediaType);
  }

  connectToPrinter(String address) {
    channel.invokeMethod("connectToPrinter", {"Address": address});
  }

  connectToGenericPrinter(String address) {
    channel.invokeMethod("connectToGenericPrinter", {"Address": address});
  }

  Future<void> print(String data) async {
    if (!data.contains("^PON")) data = data.replaceAll("^XA", "^XA^PON");

    if (isRotated) {
      data = data.replaceAll("^PON", "^POI");
    }
    await channel.invokeMethod("print", {"Data": data});
  }

  /// Imprime un Code 128 centrado al ancho real del printer.
  /// [thick] = true usa barras más gruesas (BY3); por defecto BY2.
  Future<void> printBarcode(String data, {bool thick = false}) async {
    if (Platform.isAndroid) {
      await channel.invokeMethod("printBarcode", {"Data": data, "Thick": thick});
      return;
    }
    throw UnsupportedError('Plataform don\'t support barcode yet.');
  }

  /// Imprime el barcode, la copia opcional y el footer como un único label ZPL.
  /// Al ser una sola trama, el footer no puede colarse antes de renderizar el
  /// barcode y cortarle la cola (a diferencia de llamadas separadas).
  /// [footer] son las líneas centradas debajo del barcode; [copyLabel] la línea
  /// centrada encima (p.ej. "--- COPIA ---").
  Future<void> printBarcodeWithFooter(
    String data, {
    List<String> footer = const [],
    String? copyLabel,
    bool thick = false,
  }) async {
    if (Platform.isAndroid) {
      await channel.invokeMethod("printBarcodeWithFooter", {
        "Barcode": data,
        "Footer": footer,
        "CopyLabel": copyLabel,
        "Thick": thick,
      });
      return;
    }
    throw UnsupportedError('Plataform don\'t support barcode yet.');
  }

  /// Imprime un código QR con el dato dado.
  printQrCode(String data) {
    if (Platform.isAndroid) {
      channel.invokeMethod("printQrCode", {"Data": data});
      return;
    }
    throw UnsupportedError('Plataform don\'t support QR yet.');
  }

  /// Imprime texto centrado al ancho real de impresión del printer
  /// (independiente del modelo: ZQ310 ~384, ZQ320 ~576).
  Future<void> printCenteredText(String data) async {
    if (Platform.isAndroid) {
      await channel.invokeMethod("printCenteredText", {"Data": data});
      return;
    }
    throw UnsupportedError('Plataform don\'t support centered text yet.');
  }

  /// Ancho real de impresión en dots (media.print_width).
  /// ZQ310 ~384, ZQ320 ~576. -1 si no se pudo leer (no conectado, etc).
  Future<int> getPrintWidth() async {
    if (Platform.isAndroid) {
      final int? width = await channel.invokeMethod<int>("getPrintWidth");
      return width ?? -1;
    }
    return -1;
  }

  disconnect() {
    channel.invokeMethod("disconnect", null);
  }

  calibratePrinter() {
    _setSettings(Command.calibrate, null);
  }

  isPrinterConnected() {
    channel.invokeMethod("isPrinterConnected");
  }

  rotate() {
    this.isRotated = !this.isRotated;
  }

  Future<dynamic> nativeMethodCallHandler(MethodCall methodCall) async {
    if (methodCall.method == "printerFound") {
      onPrinterFound!(
          methodCall.arguments["Name"],
          methodCall.arguments["Address"],
          methodCall.arguments["IsWifi"].toString() == "true" ? true : false);
    } else if (methodCall.method == "changePrinterStatus") {
      onChangePrinterStatus!(
          methodCall.arguments["Status"], methodCall.arguments["Color"]);
    } else if (methodCall.method == "onPrinterDiscoveryDone") {
      onPrinterDiscoveryDone!();
    } else if (methodCall.method == "onDiscoveryError") {
      onDiscoveryError!(
          methodCall.arguments["ErrorCode"], methodCall.arguments["ErrorText"]);
    }
    return null;
  }

  String? id;
}
