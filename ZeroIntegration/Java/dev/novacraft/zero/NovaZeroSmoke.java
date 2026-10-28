package dev.novacraft.zero;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;

/**
 * Original NovaCraft integration diagnostics compiled as Java 21 bytecode.
 * This does not run Minecraft, execute its classes, load LWJGL or make
 * network requests. It uses the exact static Zero VM integrated in NovaCraft.
 */
public final class NovaZeroSmoke {
    private NovaZeroSmoke() {}

    public static String probe() {
        long sum = 0L;
        for (int n = 1; n <= 1000; n++) sum += n;
        if (sum != 500500L) throw new IllegalStateException("bad integer arithmetic");
        return "ZERO_JVM_PROBE_OK Java bytecode major 65 | suma=" + sum;
    }

    /** Report relevant Java modules and basic ZIP+thread APIs without executing Minecraft. */
    public static String readiness(String clientJarPath) {
        StringBuilder out = new StringBuilder();
        out.append("ZERO_RUNTIME_JAVA: ")
            .append(System.getProperty("java.version", "unknown"))
            .append('\n');
        out.append("ZERO_VM_NAME: ")
            .append(System.getProperty("java.vm.name", "unknown"))
            .append('\n');
        out.append("ZERO_BYTECODE_MAJOR: 65\n");

        for (String module : List.of("java.base", "java.desktop", "java.logging",
                "java.xml", "java.net.http", "java.management", "jdk.unsupported")) {
            boolean present = ModuleLayer.boot().findModule(module).isPresent();
            out.append("ZERO_MODULE_")
               .append(module)
               .append(": ")
               .append(present ? "OK" : "MISSING")
               .append('\n');
        }
        try {
            // Verifies java.base compression/inflation before opening Minecraft.
            ByteArrayOutputStream data = new ByteArrayOutputStream();
            try (ZipOutputStream zip = new ZipOutputStream(data, StandardCharsets.UTF_8)) {
                zip.putNextEntry(new ZipEntry("novacraft/readiness.txt"));
                zip.write("NOVA_ZIP_OK".getBytes(StandardCharsets.UTF_8));
                zip.closeEntry();
            }
            byte[] bytes = data.toByteArray();
            try (ZipInputStream zip = new ZipInputStream(new ByteArrayInputStream(bytes))) {
                ZipEntry entry = zip.getNextEntry();
                if (entry == null || !entry.getName().equals("novacraft/readiness.txt")) {
                    throw new IllegalStateException("ZIP entry not found");
                }
                byte[] extracted = zip.readAllBytes();
                if (!Arrays.equals(extracted, "NOVA_ZIP_OK".getBytes(StandardCharsets.UTF_8))) {
                    throw new IllegalStateException("ZIP payload mismatch");
                }
            }
            out.append("ZERO_ZIP_API_OK\n");
        } catch (Throwable t) {
            out.append("ZERO_ZIP_API_FAILED: ").append(t.getClass().getSimpleName()).append('\n');
        }

        try {
            AtomicReference<String> result = new AtomicReference<>();
            Thread thread = new Thread(() -> result.set("OK"), "nova-zero-readiness");
            thread.start();
            thread.join(2000);
            out.append("ZERO_JAVA_THREADS: ")
               .append("OK".equals(result.get()) ? "OK" : "FAILED")
               .append('\n');
        } catch (Throwable t) {
            out.append("ZERO_JAVA_THREADS: FAILED ").append(t.getClass().getSimpleName()).append('\n');
        }

        if (clientJarPath == null || clientJarPath.isBlank()) {
            out.append("MINECRAFT_CLIENT_JAR: NOT_SELECTED\n");
            return out.toString();
        }
        File client = new File(clientJarPath);
        if (!client.isFile()) {
            out.append("MINECRAFT_CLIENT_JAR: NOT_DOWNLOADED_IN_THIS_APP\n");
            return out.toString();
        }

        // Only parses the archive table; does NOT classload or execute game code.
        try (ZipFile jar = new ZipFile(client)) {
            int classes = 0;
            int entries = 0;
            java.util.Enumeration<? extends ZipEntry> all = jar.entries();
            while (all.hasMoreElements()) {
                ZipEntry entry = all.nextElement();
                entries++;
                if (!entry.isDirectory() && entry.getName().endsWith(".class")) {
                    classes++;
                }
            }
            out.append("MINECRAFT_CLIENT_JAR: ZIP_READ_OK\n");
            out.append("MINECRAFT_ARCHIVE_ENTRIES: ").append(entries).append('\n');
            out.append("MINECRAFT_CLASS_FILES: ").append(classes).append('\n');
            if (classes < 1000) {
                out.append("MINECRAFT_ARCHIVE_WARNING: unusually few .class files\n");
            }
        } catch (Throwable t) {
            out.append("MINECRAFT_CLIENT_JAR: ZIP_READ_FAILED ")
               .append(t.getClass().getSimpleName()).append('\n');
        }
        out.append("MINECRAFT_EXECUTION: NOT_ATTEMPTED\n");
        out.append("LWJGL_OPENGL: NOT_TESTED\n");
        return out.toString();
    }
}
