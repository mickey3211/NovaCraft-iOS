package dev.novacraft.zero;

/** Original NovaCraft integration probe compiled with --release 21. */
public final class NovaZeroSmoke {
    private NovaZeroSmoke() {}
    public static String probe() {
        long sum = 0L;
        for (int n = 1; n <= 1000; n++) sum += n;
        if (sum != 500500L) throw new IllegalStateException("bad integer arithmetic");
        return "ZERO_JVM_PROBE_OK Java bytecode major 65 | suma=" + sum;
    }
}
