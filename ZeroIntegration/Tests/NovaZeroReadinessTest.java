import dev.novacraft.zero.NovaZeroSmoke;
import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

/** Synthetic headers test the scanner, not JVM verification or Minecraft execution. */
public final class NovaZeroReadinessTest {
    private static final String MAIN = "net/minecraft/client/main/Main.class";
    private static int passed;

    private static byte[] header(int magic, int minor, int major) throws Exception {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (DataOutputStream data = new DataOutputStream(bytes)) {
            data.writeInt(magic);
            data.writeShort(minor);
            data.writeShort(major);
        }
        return bytes.toByteArray();
    }

    private static String inspect(String name, byte[] bytes) throws Exception {
        Path jar = Files.createTempFile("nova-readiness-", ".jar");
        try {
            try (ZipOutputStream zip = new ZipOutputStream(Files.newOutputStream(jar))) {
                zip.putNextEntry(new ZipEntry(name));
                zip.write(bytes);
                zip.closeEntry();
            }
            return NovaZeroSmoke.readiness(jar.toString());
        } finally { Files.deleteIfExists(jar); }
    }

    private static void contains(String report, String expected) {
        if (!report.contains(expected + "\n")) {
            throw new AssertionError("Missing " + expected + " in:\n" + report);
        }
        passed++;
    }

    public static void main(String[] args) throws Exception {
        int major = Runtime.version().feature() + 44;
        String valid = inspect(MAIN, header(0xCAFEBABE, 0, major));
        contains(valid, "MINECRAFT_BASE_CLASS_HEADERS: COMPATIBLE");
        contains(valid, "MINECRAFT_MODERN_ENTRYPOINT: PRESENT");
        contains(valid, "MINECRAFT_MAX_CLASS_MAJOR: " + major);
        contains(valid, "MINECRAFT_EXECUTION: NOT_ATTEMPTED");
        contains(valid, "ZERO_ZIP_API_OK");
        contains(valid, "ZERO_JAVA_THREADS: OK");
        contains(inspect(MAIN, header(0xCAFEBABE, 0, major + 1)),
                 "MINECRAFT_UNSUPPORTED_CLASS_HEADERS: 1");
        contains(inspect(MAIN, header(0xCAFEBABE, 65535, major)),
                 "MINECRAFT_UNSUPPORTED_CLASS_HEADERS: 1");
        contains(inspect(MAIN, header(0xCAFEBABE, 1, 65)),
                 "MINECRAFT_INVALID_CLASS_HEADERS: 1");
        contains(inspect(MAIN, header(0, 0, major)), "MINECRAFT_INVALID_CLASS_HEADERS: 1");
        contains(inspect(MAIN, new byte[] {1, 2}), "MINECRAFT_BASE_CLASS_HEADERS: FAILED");
        contains(inspect("assets/readme.txt", new byte[0]), "MINECRAFT_BASE_CLASS_HEADERS: FAILED");
        contains(inspect("other/Test.class", header(0xCAFEBABE, 0, major)),
                 "MINECRAFT_MODERN_ENTRYPOINT: MISSING");
        String versioned = inspect("META-INF/versions/99/Test.class", header(0xCAFEBABE, 0, 143));
        contains(versioned, "MINECRAFT_VERSIONED_CLASSES_NOT_CHECKED: 1");
        contains(versioned, "MINECRAFT_UNSUPPORTED_CLASS_HEADERS: 0");
        contains(NovaZeroSmoke.readiness(""), "MINECRAFT_CLIENT_JAR: NOT_SELECTED");
        Path corrupt = Files.createTempFile("nova-corrupt-", ".jar");
        try {
            Files.writeString(corrupt, "not a ZIP");
            contains(NovaZeroSmoke.readiness(corrupt.toString()),
                     "MINECRAFT_CLIENT_JAR: ZIP_READ_FAILED ZipException");
        } finally { Files.deleteIfExists(corrupt); }
        System.out.println("Nova Zero readiness: " + passed + " checks passed");
    }
}
