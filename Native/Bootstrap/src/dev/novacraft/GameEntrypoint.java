/*
 * Copyright (c) 2026 mickey3211. All rights reserved for NovaCraft-original code.
 *
 * A tiny diagnostic trampoline, compiled to Java 8-compatible bytecode.
 * This is independent NovaCraft code, not copied from another launcher.
 * No credentials or game argument values are logged.
 */
package dev.novacraft;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.Arrays;

public final class GameEntrypoint {
    private GameEntrypoint() {}

    public static void main(String[] args) throws Exception {
        System.err.println("[NovaCraft] JVM_ENTRY_REACHED");
        System.err.println("[NovaCraft] Java runtime: " + System.getProperty("java.version", "unknown"));
        System.err.println("[NovaCraft] Architecture: " + System.getProperty("os.arch", "unknown"));
        System.err.flush();

        if (Boolean.getBoolean("novacraft.jvmProbeOnly")) {
            System.err.println("[NovaCraft] JVM_PROBE_OK - Java bytecode ran successfully.");
            System.err.flush();
            return;
        }

        if (args.length == 0) {
            throw new IllegalArgumentException("Missing Minecraft entrypoint class");
        }
        final String target = args[0];
        if (target.equals(GameEntrypoint.class.getName())) {
            throw new IllegalArgumentException("Recursive bootstrap target");
        }
        // Never print or persist the game argument values: they may contain
        // Microsoft authentication credentials on future online launches.
        final String[] gameArguments = Arrays.copyOfRange(args, 1, args.length);
        System.err.println("[NovaCraft] MC_MAIN_CLASS_LOADING");
        System.err.flush();
        final Class<?> minecraft = Class.forName(target);
        final Method main = minecraft.getMethod("main", String[].class);
        System.err.println("[NovaCraft] MC_MAIN_ENTERING");
        System.err.flush();
        try {
            main.invoke(null, (Object) gameArguments);
            System.err.println("[NovaCraft] MC_MAIN_RETURNED");
            System.err.flush();
        } catch (InvocationTargetException failure) {
            final Throwable cause = failure.getCause() != null ? failure.getCause() : failure;
            System.err.println("[NovaCraft] MC_MAIN_THROWN: " + cause.getClass().getName());
            // The throwable stack may include filesystem paths; users are warned
            // to redact diagnostics before sharing. Never auto-upload any log.
            cause.printStackTrace(System.err);
            System.err.flush();
            throw new IllegalStateException("Minecraft failed to initialize", cause);
        }
    }
}
