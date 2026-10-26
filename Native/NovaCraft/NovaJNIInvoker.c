#include "NovaJNIInvoker.h"
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>

// Persist only diagnostic stages, never account credentials or game arguments.
// A native JVM crash prevents Swift error handling, so the next app start can
// show the last completed stage to the user.
static void nova_checkpoint(const char *stage) {
    const char *home = getenv("HOME");
    if (!home || !stage) return;
    char path[PATH_MAX];
    int n = snprintf(path, sizeof(path), "%s/Documents/NovaCraft-jvm-last-stage.txt", home);
    if (n <= 0 || (size_t)n >= sizeof(path)) return;
    FILE *out = fopen(path, "w");
    if (!out) return;
    fputs(stage, out);
    fputc(10, out);
    fflush(out);
    fsync(fileno(out));
    fclose(out);
}

// JNI invocation ABI. Function table slots follow the published JNI specification.
// Using a small C ABI bridge avoids importing desktop-only JDK headers into Xcode.
typedef int32_t jint;
typedef uint8_t jboolean;
typedef void *jobject;
typedef jobject jclass;
typedef jobject jstring;
typedef jobject jobjectArray;
typedef void *jmethodID;
typedef struct {
    char *optionString;
    void *extraInfo;
} JavaVMOption;
typedef struct {
    jint version;
    jint nOptions;
    JavaVMOption *options;
    jboolean ignoreUnrecognized;
} JavaVMInitArgs;

typedef jint (*CreateVM)(void **, void **, void *);
typedef jclass (*FindClass)(void *, const char *);
typedef jmethodID (*GetStaticMethodID)(void *, jclass, const char *, const char *);
typedef jobjectArray (*NewObjectArray)(void *, jint, jclass, jobject);
typedef jstring (*NewStringUTF)(void *, const char *);
typedef void (*SetObjectArrayElement)(void *, jobjectArray, jint, jobject);
typedef void (*CallStaticVoidMethodA)(void *, jclass, jmethodID, const void *);
typedef jboolean (*ExceptionCheck)(void *);
typedef void (*ExceptionDescribe)(void *);
typedef void (*DeleteLocalRef)(void *, jobject);

static int already_started = 0;
static void *retained_library = NULL;

int nova_jni_invoke_main(const char *runtime_path,
                         const char *main_class,
                         const char *classpath,
                         const char *native_path,
                         const char * const *jvm_options,
                         int jvm_option_count,
                         const char * const *game_args,
                         int game_arg_count) {
    if (already_started) return -10; // A JVM cannot safely be restarted in process.
    if (!runtime_path || !main_class || !classpath || !native_path ||
        !game_args || game_arg_count < 0 || game_arg_count > 1024 ||
        jvm_option_count < 0 || jvm_option_count > 128 ||
        (jvm_option_count > 0 && !jvm_options)) return -11;
    // OpenJDK on iOS needs a coherent JAVA_HOME and the native JLI bootstrap
    // dependency available to the dynamic loader before JNI_CreateJavaVM.
    // Keep this initialized from the signed, bundled runtime only.
    char java_home[PATH_MAX] = {0};
    const char *framework_marker = strstr(runtime_path, "/NovaJava21.framework/");
    if (framework_marker) {
        size_t len = (size_t)(framework_marker - runtime_path) +
                     strlen("/NovaJava21.framework");
        if (len >= sizeof(java_home)) return -25;
        memcpy(java_home, runtime_path, len);
        java_home[len] = '\\0';
        setenv("JAVA_HOME", java_home, 1);
        char jli_path[PATH_MAX];
        int n = snprintf(jli_path, sizeof(jli_path), "%s/lib/libjli.dylib", java_home);
        if (n <= 0 || (size_t)n >= sizeof(jli_path)) return -26;
        nova_checkpoint("Ładowanie Java Launcher Interface (libjli)");
        if (access(jli_path, R_OK) == 0) {
            void *jli = dlopen(jli_path, RTLD_NOW | RTLD_GLOBAL);
            if (!jli) {
                nova_checkpoint("Błąd ładowania libjli.dylib");
                return -27;
            }
        } else {
            nova_checkpoint("Brak libjli.dylib w Java 21");
            return -28;
        }
    }
    nova_checkpoint("Ładowanie biblioteki JVM (dlopen)");
    void *library = dlopen(runtime_path, RTLD_NOW | RTLD_LOCAL);
    if (!library) return -12;
    nova_checkpoint("JVM załadowana; wyszukiwanie JNI_CreateJavaVM");
    CreateVM create = (CreateVM)dlsym(library, "JNI_CreateJavaVM");
    if (!create) { dlclose(library); return -13; }

    size_t classpath_size = strlen(classpath) + 20;
    size_t native_size = strlen(native_path) + 22;
    char *cp = calloc(classpath_size, 1);
    char *np = calloc(native_size, 1);
    if (!cp || !np) {
        free(cp); free(np); dlclose(library); return -14;
    }
    snprintf(cp, classpath_size, "-Djava.class.path=%s", classpath);
    snprintf(np, native_size, "-Djava.library.path=%s", native_path);
    JavaVMOption options[131] = {0};
    options[0].optionString = cp;
    options[1].optionString = np;
    options[2].optionString = "-Xmx768m";
    for (int i = 0; i < jvm_option_count; i++) {
        if (jvm_options[i] && strncmp(jvm_options[i], "-Xmx", 4) == 0) {
            options[2].optionString = (char *)jvm_options[i];
            break;
        }
    }
    for (int i = 0; i < jvm_option_count; i++) {
        options[i + 3].optionString = (jvm_options[i] && strncmp(jvm_options[i], "-Xmx", 4) == 0)
            ? "-Dnovacraft.heap.selected=true" : (char *)jvm_options[i];
    }
    JavaVMInitArgs init = {0x00010008, jvm_option_count + 3, options, 0};
    void *vm = NULL;
    void *env = NULL;
    nova_checkpoint("Tworzenie maszyny Java (JNI_CreateJavaVM)");
    jint result = create(&vm, &env, &init);
    free(cp);
    free(np);
    if (result != 0 || !vm || !env) {
        dlclose(library);
        return result != 0 ? result : -15;
    }
    nova_checkpoint("Maszyna Java utworzona; wczytywanie klasy Minecraft");
    already_started = 1;
    retained_library = library;

    void **functions = *(void ***)env;
    if (!functions) return -16;
    FindClass findClass = (FindClass)functions[6];
    GetStaticMethodID getStaticMethodID = (GetStaticMethodID)functions[113];
    NewStringUTF newStringUTF = (NewStringUTF)functions[167];
    NewObjectArray newObjectArray = (NewObjectArray)functions[172];
    SetObjectArrayElement setArrayElement = (SetObjectArrayElement)functions[174];
    CallStaticVoidMethodA callMain = (CallStaticVoidMethodA)functions[143];
    ExceptionCheck hasException = (ExceptionCheck)functions[228];
    ExceptionDescribe describeException = (ExceptionDescribe)functions[16];
    DeleteLocalRef deleteLocalRef = (DeleteLocalRef)functions[23];

    size_t length = strlen(main_class);
    char *class_name = malloc(length + 1);
    if (!class_name) return -17;
    memcpy(class_name, main_class, length + 1);
    for (size_t i = 0; i < length; i++) {
        if (class_name[i] == '.') class_name[i] = '/';
    }
    nova_checkpoint("Wyszukiwanie klasy głównej Minecraft");
    jclass entry = findClass(env, class_name);
    free(class_name);
    if (!entry || hasException(env)) {
        describeException(env);
        return -18;
    }
    jmethodID method = getStaticMethodID(env, entry, "main", "([Ljava/lang/String;)V");
    if (!method || hasException(env)) {
        describeException(env);
        return -19;
    }
    jclass stringClass = findClass(env, "java/lang/String");
    if (!stringClass || hasException(env)) {
        describeException(env);
        return -20;
    }
    jobjectArray args = newObjectArray(env, game_arg_count, stringClass, NULL);
    if (!args || hasException(env)) {
        describeException(env);
        return -21;
    }
    for (int i = 0; i < game_arg_count; i++) {
        jstring value = newStringUTF(env, game_args[i] ? game_args[i] : "");
        if (!value || hasException(env)) {
            describeException(env);
            return -22;
        }
        setArrayElement(env, args, i, value);
        deleteLocalRef(env, value);
        if (hasException(env)) {
            describeException(env);
            return -23;
        }
    }
    // JNI jvalue union: a single jobject argument occupies pointer-sized storage.
    jobject parameter = args;
    nova_checkpoint("Uruchamianie Minecraft main() i grafiki LWJGL");
    callMain(env, entry, method, &parameter);
    if (hasException(env)) {
        describeException(env);
        return -24;
    }
    nova_checkpoint("Minecraft main() zakończyła działanie");
    return 0;
}
