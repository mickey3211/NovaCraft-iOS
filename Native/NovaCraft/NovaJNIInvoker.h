#ifndef NOVA_JNI_INVOKER_H
#define NOVA_JNI_INVOKER_H

#ifdef __cplusplus
extern "C" {
#endif

// Static OpenJDK Mobile Zero integration proof (from the independently
// tested NovaCraft Zero app). Runs a Java 21 classfile on a dedicated thread.
// Returns 0 only if Java bytecode executed. Does not launch Minecraft.
int nova_zero_run_smoke_test(void);

// Runs Java main(String[]) in an already bundled, code-signed iOS JVM.
// Returns 0 on success, negative values for bridge errors, or a JNI error code.
// Must be called from a dedicated background thread. JVM stays resident.
int nova_jni_invoke_main(const char *runtime_path,
                         const char *main_class,
                         const char *classpath,
                         const char *native_path,
                         const char * const *jvm_options,
                         int jvm_option_count,
                         const char * const *game_args,
                         int game_arg_count);

// OpenJDK iOS's Java Launcher Interface: alternate bootstrap when direct
// JNI_CreateJavaVM fails before running Minecraft. Uses bundled libjli.
int nova_jli_launch_main(const char *runtime_path,
                         const char *main_class,
                         const char *classpath,
                         const char *native_path,
                         const char * const *jvm_options,
                         int jvm_option_count,
                         const char * const *game_args,
                         int game_arg_count);

#ifdef __cplusplus
}
#endif
#endif
