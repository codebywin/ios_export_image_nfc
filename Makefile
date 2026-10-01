TARGET := iphone:clang:latest:15.0
ARCHS  := arm64 arm64e

# Hỗ trợ cả Rootless (Dopamine) và RootHide: make package THEOS_PACKAGE_SCHEME=roothide
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ExportImageNFC

ExportImageNFC_FILES = main.m \
                       AppDelegate.m \
                       MainViewController.m \
                       CCCDReaderManager.m \
                       BACSession.m \
                       CryptoUtils.m \
                       DG2Parser.m \
                       MRZScannerViewController.m

ExportImageNFC_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function -Oz
ExportImageNFC_FRAMEWORKS = UIKit CoreNFC Foundation CoreGraphics Photos AVFoundation Vision Security ImageIO
ExportImageNFC_CODESIGN_FLAGS = -SExportImageNFC.entitlements

# Theos rootless/roothide tự động gán prefix đường dẫn cài đặt
ExportImageNFC_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/application.mk
