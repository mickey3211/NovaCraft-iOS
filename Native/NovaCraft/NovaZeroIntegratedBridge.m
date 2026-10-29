// Copyright (c) 2026 mickey3211. Original NovaCraft Zero integration.
// The OpenJDK Mobile statically linked Zero VM is a separately licensed
// third-party component, and does not implement Minecraft or LWJGL.
#import <Foundation/Foundation.h>
#include <jni.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>


static atomic_bool zeroStarted = false;

static NSString *zeroLogURL(void) {
    NSString *folder = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                           NSUserDomainMask, YES).firstObject;
    return [folder stringByAppendingPathComponent:@"NovaCraft-integrated-zero.log"];
}

static void zeroLog(NSString *line) {
    FILE *f = fopen(zeroLogURL().fileSystemRepresentation, "a");
    if (!f) return;
    fprintf(f, "%s\n", line.UTF8String ?: "(invalid utf8)");
    fflush(f);
    fclose(f);
}

// This function is called ONLY on a dedicated Java thread, not the
// SwiftUI main thread. Once Java is created it remains active in-process.
// Multiple simultaneous Zero or HotSpot instances are not supported.
int nova_zero_run_smoke_test(const char *minecraft_version) {
    bool previous = atomic_exchange(&zeroStarted, true);
    if (previous) {
        zeroLog(@"ZERO_INTEGRATION: JVM already started; restart app for another test.");
        return -90;
    }

    @autoreleasepool {
        NSString *root = NSBundle.mainBundle.resourcePath;
        NSString *jar = [root stringByAppendingPathComponent:@"NovaZeroSmoke.jar"];
        NSString *modules = [root stringByAppendingPathComponent:@"lib/lib/modules"];
        // Replace earlier report on every new launch. Persistent log survives a
        // crash and may be shared manually, never auto-uploaded.
        [@"NovaCraft Zero inside SwiftUI launcher\n" writeToFile:zeroLogURL()
                                                        atomically:YES encoding:NSUTF8StringEncoding error:nil];
        if (![NSFileManager.defaultManager fileExistsAtPath:jar] ||
            ![NSFileManager.defaultManager fileExistsAtPath:modules]) {
            zeroLog(@"ZERO_FAILED: missing Java smoke jar or bundled Zero modules.");
            return -91;
        }
        zeroLog([NSString stringWithFormat:@"APP_BUILD: %@", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]]);
        zeroLog([NSString stringWithFormat:@"REPORT_DATE: %@", NSDate.date]);
        zeroLog(@"ZERO_INTEGRATION: static OpenJDK Mobile Zero linked into NovaCraft.");
        zeroLog(@"ZERO_STEP: JNI entrypoints retained from matching static runtime at link time");

        NSString *classpath = [@"-Djava.class.path=" stringByAppendingString:jar];
        const char *opts[] = {classpath.UTF8String, "-Xms16m", "-Xmx128m"};
        JavaVMOption options[3] = {0};
        for (int i = 0; i < 3; ++i) options[i].optionString = (char *)opts[i];

        JavaVMInitArgs args = {0};
        args.version = JNI_VERSION_1_8;
        args.nOptions = 3;
        args.options = options;
        args.ignoreUnrecognized = JNI_FALSE;
        JavaVM *vm = NULL;
        JNIEnv *env = NULL;
        zeroLog(@"ZERO_STEP: JNI_CreateJavaVM started");
        jint result = JNI_CreateJavaVM(&vm, (void **)&env, &args);
        zeroLog([NSString stringWithFormat:@"ZERO_STEP: JNI_CreateJavaVM returned %d", (int)result]);
        if (result != JNI_OK || !env) return -92;

        jclass cls = (*env)->FindClass(env, "dev/novacraft/zero/NovaZeroSmoke");
        if (!cls || (*env)->ExceptionCheck(env)) {
            (*env)->ExceptionDescribe(env);
            (*env)->ExceptionClear(env);
            zeroLog(@"ZERO_FAILED: FindClass");
            return -93;
        }
        jmethodID probe = (*env)->GetStaticMethodID(env, cls, "probe", "()Ljava/lang/String;");
        if (!probe || (*env)->ExceptionCheck(env)) {
            (*env)->ExceptionDescribe(env);
            (*env)->ExceptionClear(env);
            zeroLog(@"ZERO_FAILED: probe method");
            return -94;
        }
        jstring output = (jstring)(*env)->CallStaticObjectMethod(env, cls, probe);
        if (!output || (*env)->ExceptionCheck(env)) {
            (*env)->ExceptionDescribe(env);
            (*env)->ExceptionClear(env);
            zeroLog(@"ZERO_FAILED: Java probe threw exception");
            return -95;
        }
        const char *utf = (*env)->GetStringUTFChars(env, output, NULL);
        if (!utf) return -96;
        NSString *message = [NSString stringWithUTF8String:utf] ?: @"ZERO_FAILED: invalid utf8";
        (*env)->ReleaseStringUTFChars(env, output, utf);
        (*env)->DeleteLocalRef(env, output);
        zeroLog(message);
        if (![message hasPrefix:@"ZERO_JVM_PROBE_OK"]) {
            zeroLog(@"ZERO_FAILED: unexpected Java result");
            return -97;
        }
        zeroLog(@"NOVA_ZERO_INTEGRATED_OK: JNI ran Java 21 class bytecode inside NovaCraft SwiftUI.");

        // Next diagnostic phase: check real Zero modules, Java ZIP and thread
        // APIs, and optionally parse an installed client.jar without running
        // Minecraft, loading native libraries, or touching Microsoft tokens.
        // Validate the version component so untrusted text cannot construct
        // a path outside Application Support/NovaCraft/versions/.
        NSString *version = minecraft_version
            ? [NSString stringWithUTF8String:minecraft_version] : @"";
        NSCharacterSet *allowed =
            [NSCharacterSet characterSetWithCharactersInString:
             @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
        NSString *clientPath = @"";
        if (version.length > 0 && version.length <= 80 &&
            [version rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound &&
            ![version isEqualToString:@"."] && ![version isEqualToString:@".."]) {
            zeroLog([@"MINECRAFT_SELECTED_VERSION: " stringByAppendingString:version]);
            NSString *support = NSSearchPathForDirectoriesInDomains(
                NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
            clientPath = [[[[support stringByAppendingPathComponent:@"NovaCraft"]
                             stringByAppendingPathComponent:@"versions"]
                             stringByAppendingPathComponent:version]
                             stringByAppendingPathComponent:@"client.jar"];
        }
        jmethodID readiness = (*env)->GetStaticMethodID(
            env, cls, "readiness", "(Ljava/lang/String;)Ljava/lang/String;");
        if (!readiness || (*env)->ExceptionCheck(env)) {
            (*env)->ExceptionDescribe(env);
            (*env)->ExceptionClear(env);
            zeroLog(@"ZERO_READINESS_ERROR: readiness method unavailable");
        } else {
            jstring path = (*env)->NewStringUTF(env, clientPath.UTF8String);
            jstring output = path ? (jstring)(*env)->CallStaticObjectMethod(
                env, cls, readiness, path) : NULL;
            if ((*env)->ExceptionCheck(env) || !output) {
                (*env)->ExceptionDescribe(env);
                (*env)->ExceptionClear(env);
                zeroLog(@"ZERO_READINESS_ERROR: Java readiness threw");
            } else {
                const char *text = (*env)->GetStringUTFChars(env, output, NULL);
                if (text) {
                    zeroLog([NSString stringWithUTF8String:text] ?: @"ZERO_READINESS: bad UTF8");
                    (*env)->ReleaseStringUTFChars(env, output, text);
                }
                (*env)->DeleteLocalRef(env, output);
            }
            if (path) (*env)->DeleteLocalRef(env, path);
        }

        (*env)->DeleteLocalRef(env, cls);
        zeroLog(@"Minecraft bytecode was NOT run. GLFW/OpenGL are NOT ready.");
        // Zero remains alive until the iOS app is stopped; do not call
        // DestroyJavaVM from an on-screen button (may block indefinitely).
        return 0;
    }
}
