//
//  BuildInfo.swift
//  JoeCalendar
//
//  Fallback template for BuildInfo. When building via Xcode or build script,
//  JoeCalendar/Generated/BuildInfo.generated.swift is produced and compiled.
//

import Foundation

#if NO_GENERATED_BUILD_INFO
public let APP_VERSION = "1.0.0"
public let GIT_HASH = "dev"
public let BUILD_DATE = ""
#endif
