#include "NovaJNIInvoker.h"
#include <dlfcn.h>
#include <fcntl.h>
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

// Include dyld's concrete failure reason in the next-start crash diagnostics.
static void nova_checkpoint_loader_failure(const char *stage) {
    const char *reason = dlerror();
    char report[768];
    snprintf(report, sizeof(report), "%.120s: %.590s", stage,
             reason ? reason : "brak szczegółów od iOS dyld");
    nova_checkpoint(report);
}

// Capture JVM stdout/stderr for an explicit user-initiated diagnostics export.
// JLI may return without a crash when Minecraft fails before a window exists.
// Logs stay in the app sandbox; they can contain usernames, server addresses,
// filesystem paths or other sensitive information and must not be uploaded
// automatically. Restore global file descriptors when the launch returns.
static void nova_begin_java_log(int *saved_stdout, int *saved_stderr) {
    *saved_stdout = -1;
    *saved_stderr = -1;
    const char *home = getenv("HOME");
    if (!home) return;
    char path[PATH_MAX];
    int n = snprintf(path, sizeof(path), "%s/Documents/NovaCraft-java-output.log", home);
    if (n <= 0 || (size_t)n >= sizeof(path)) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return;
    fflush(NULL);
    int stdout_copy = dup(STDOUT_FILENO);
    int stderr_copy = dup(STDERR_FILENO);
    if (stdout_copy < 0 || stderr_copy < 0) {
        if (stdout_copy >= 0) close(stdout_copy);
        if (stderr_copy >= 0) close(stderr_copy);
        close(fd);
        return;
    }
    if (dup2(fd, STDOUT_FILENO) < 0 || dup2(fd, STDERR_FILENO) < 0) {
        dup2(stdout_copy, STDOUT_FILENO);
        dup2(stderr_copy, STDERR_FILENO);
        close(stdout_copy);
        close(stderr_copy);
        close(fd);
        return;
    }
    close(fd);
    *saved_stdout = stdout_copy;
    *saved_stderr = stderr_copy;
    fprintf(stderr, "[NovaCraft] Java 21 JLI launch started.\n");
    fflush(stderr);
}

static void nova_end_java_log(int saved_stdout, int saved_stderr, int exit_code) {
    if (saved_stdout < 0 || saved_stderr < 0) return;
    fprintf(stderr, "[NovaCraft] Java launcher returned exit code %d.\n", exit_code);
    fflush(NULL);
    dup2(saved_stdout, STDOUT_FILENO);
    dup2(saved_stderr, STDERR_FILENO);
    close(saved_stdout);
    close(saved_stderr);
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
        java_home[len] = 0;
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
    if (!library) { nova_checkpoint_loader_failure("JNI: nie można załadować libjvm"); return -12; }
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


// OpenJDK iOS bootstrap through libjli rather than direct JNI_CreateJavaVM.
// This is an independent adapter to OpenJDK's public Java Launcher Interface,
// not a copy of another launcher's code. Both startup paths must be tested
// on a physical device: these libraries require compatible code signing.
typedef jint (*NovaJLILaunch)(int, const char **, int, const char **,
                              int, const char **, const char *, const char *,
                              const char *, const char *, jboolean,
                              jboolean, jboolean, jint);

int nova_jli_launch_main(const char *runtime_path,
                         const char *main_class,
                         const char *classpath,
                         const char *native_path,
                         const char * const *jvm_options,
                         int jvm_option_count,
                         const char * const *game_args,
                         int game_arg_count) {
    if (already_started) return -10;
    if (!runtime_path || !main_class || !classpath || !native_path ||
        game_arg_count < 0 || game_arg_count > 1024 ||
        jvm_option_count < 0 || jvm_option_count > 128 ||
        (game_arg_count > 0 && !game_args) ||
        (jvm_option_count > 0 && !jvm_options)) return -11;

    // Use only the bundled and reviewed JRE21. No downloaded executable code.
    const char *marker = strstr(runtime_path, "/NovaJava21.framework/");
    if (!marker) return -40;
    size_t len = (size_t)(marker - runtime_path) + strlen("/NovaJava21.framework");
    char home[PATH_MAX], jli_path[PATH_MAX], java_exe[PATH_MAX];
    if (len >= sizeof(home)) return -41;
    memcpy(home, runtime_path, len);
    home[len] = 0;
    if (snprintf(jli_path, sizeof(jli_path), "%s/lib/libjli.dylib", home) >= sizeof(jli_path) ||
        snprintf(java_exe, sizeof(java_exe), "%s/bin/java", home) >= sizeof(java_exe)) return -42;
    // The bundled iOS JRE may intentionally omit its desktop 'bin/java'
    // executable. The Java Launcher Interface uses the argv[0] string to
    // locate JAVA_HOME; it does not execute that file. Keep verifying the
    // actual signed libjli and libjvm dylibs below.
    if (access(java_exe, R_OK) != 0) {
        nova_checkpoint("JLI: bin/java pominięto w iOS JRE; używam ścieżki argv[0]");
    }
    if (access(runtime_path, R_OK) != 0) {
        nova_checkpoint("JLI: brak dostępnego pliku libjvm.dylib w podpisanym Java 21");
        return -52;
    }
    if (access(jli_path, R_OK) != 0) {
        nova_checkpoint("JLI: brak podpisanej biblioteki libjli.dylib");
        return -43;
    }

    setenv("JAVA_HOME", home, 1);
    setenv("INTERNAL_JLI_PATH", jli_path, 1);
    setenv("HACK_IGNORE_START_ON_FIRST_THREAD", "1", 1);
    nova_checkpoint("JLI: ładowanie libjli.dylib");
    void *handle = dlopen(jli_path, RTLD_NOW | RTLD_GLOBAL);
    if (!handle) {
        nova_checkpoint_loader_failure("JLI: nie można załadować libjli.dylib");
        return -44;
    }
    NovaJLILaunch launch = (NovaJLILaunch)dlsym(handle, "JLI_Launch");
    if (!launch) {
        nova_checkpoint("JLI: brak symbolu JLI_Launch w bibliotece");
        return -45;
    }

    // The iPhone signer must sign native code *inside* JAVA_HOME too.
    // Check this before invoking JLI: otherwise dyld can kill the whole app
    // during JVM startup and Swift never gets a chance to display an error.
    char nested_vm_path[PATH_MAX];
    int vm_path_length = snprintf(nested_vm_path, sizeof(nested_vm_path),
                                  "%s/lib/server/libjvm.dylib", home);
    if (vm_path_length < 0 || (size_t)vm_path_length >= sizeof(nested_vm_path)) {
        nova_checkpoint("JLI: ścieżka do libjvm jest zbyt długa");
        return -48;
    }
    nova_checkpoint("JLI: weryfikowanie podpisu i zależności libjvm.dylib");
    void *nested_vm = dlopen(nested_vm_path, RTLD_NOW | RTLD_GLOBAL);
    if (!nested_vm) {
        const char *reason = dlerror();
        char report[512];
        snprintf(report, sizeof(report), "JLI: nie można otworzyć libjvm (podpis lub zależności): %.360s",
                 reason ? reason : "nieznany błąd");
        nova_checkpoint(report);
        return -49;
    }
    if (!dlsym(nested_vm, "JNI_CreateJavaVM")) {
        nova_checkpoint("JLI: wbudowana libjvm nie udostępnia JNI_CreateJavaVM");
        return -50;
    }
    nova_checkpoint("JLI: libjvm załadowana; przygotowanie Java 21");

    size_t argc = (size_t)jvm_option_count + (size_t)game_arg_count + 12;
    const char **argv = calloc(argc, sizeof(*argv));
    if (!argv) return -46;
    char *native_property = malloc(strlen(native_path) + 23);
    if (!native_property) { free(argv); return -47; }
    sprintf(native_property, "-Djava.library.path=%s", native_path);

    size_t i = 0;
    argv[i++] = java_exe; // argv[0] indicates the Java home to JLI.
    argv[i++] = "-XX:+UnlockExperimentalVMOptions";
    argv[i++] = "-XX:+DisablePrimordialThreadGuardPages";
    argv[i++] = native_property;
    for (int k = 0; k < jvm_option_count; k++) {
        if (jvm_options[k]) argv[i++] = jvm_options[k];
    }
    argv[i++] = "-cp";
    argv[i++] = classpath;
    argv[i++] = main_class;
    for (int k = 0; k < game_arg_count; k++) {
        argv[i++] = game_args[k] ? game_args[k] : "";
    }

    already_started = 1;
    retained_library = handle;
    nova_checkpoint("JLI: uruchamianie środowiska Java 21 i klasy Minecraft");
    int saved_stdout = -1, saved_stderr = -1;
    nova_begin_java_log(&saved_stdout, &saved_stderr);
    jint result = launch((int)i, argv, 0, NULL, 0, NULL,
                         "21", "21", "java", "openjdk",
                         0, 1, 0, 1);
    nova_end_java_log(saved_stdout, saved_stderr, result);
    nova_checkpoint(result == 0 ? "JLI: Minecraft zakończył działanie" :
                                  "JLI: proces Java zakończył się błędem");
    free(native_property);
    free(argv);
    return result;
}
