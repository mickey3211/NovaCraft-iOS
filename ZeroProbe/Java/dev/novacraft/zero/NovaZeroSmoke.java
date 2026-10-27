package dev.novacraft.zero;

// Original small Java test class for the NovaCraft Zero VM proof.
// Compiled with --release 21 to test a Java 21 class file on iPhone.
public final class NovaZeroSmoke {
    private NovaZeroSmoke() {}

    public static String probe() {
        long value = 0;
        for (int i = 1; i <= 1000; i++) {
            value += i;
        }
        if (value != 500500) {
            throw new IllegalStateException("Test matematyczny JVM nie powiodl sie");
        }
        String text = "ZERO_JVM_PROBE_OK Java bytecode major 65 | suma=" + value;
        if (text.length() < 25) {
            throw new IllegalStateException("Blad String na JVM");
        }
        return text;
    }
}
