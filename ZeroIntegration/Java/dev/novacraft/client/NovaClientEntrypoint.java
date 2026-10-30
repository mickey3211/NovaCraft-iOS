package dev.novacraft.client;

import java.lang.reflect.InvocationTargetException;
import java.util.Arrays;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

/** Normal client bootstrap: records failures even before Minecraft configures logging. */
public final class NovaClientEntrypoint {
    public static void main(String[] arguments) throws Throwable {
        if (arguments.length == 0) throw new IllegalArgumentException("Missing client entrypoint");
        AtomicBoolean running = new AtomicBoolean(true);
        Thread launchThread = Thread.currentThread();
        Thread progress = new Thread(() -> {
            for (int sample = 1; sample <= 3; sample++) {
                try { Thread.sleep(30000); } catch (InterruptedException stopped) { return; }
                if (!running.get()) return;
                System.err.println("NOVA_LAUNCH_STACK elapsed=" + (sample * 30) + "s (not a timeout)");
                dump(launchThread, launchThread.getStackTrace());
                int count = 0;
                for (Map.Entry<Thread, StackTraceElement[]> entry : Thread.getAllStackTraces().entrySet()) {
                    if (entry.getKey() == launchThread || entry.getKey() == Thread.currentThread()) continue;
                    if (++count > 24) break;
                    dump(entry.getKey(), entry.getValue());
                }
                System.err.flush();
            }
        }, "NovaCraft-Launch-Progress");
        progress.setDaemon(true);
        progress.start();
        try {
            System.err.println("NOVA_CLIENT_CLASS_LOADING: " + arguments[0]);
            Class<?> client = Class.forName(arguments[0]);
            System.err.println("NOVA_CLIENT_MAIN_ENTER");
            client.getMethod("main", String[].class).invoke(null, (Object)Arrays.copyOfRange(arguments, 1, arguments.length));
            System.err.println("NOVA_CLIENT_MAIN_RETURN");
        } catch (InvocationTargetException error) {
            Throwable cause = error.getCause();
            System.err.println("NOVA_CLIENT_MAIN_FAILED");
            cause.printStackTrace(System.err);
            throw cause;
        } catch (Throwable error) {
            System.err.println("NOVA_CLIENT_BOOTSTRAP_FAILED");
            error.printStackTrace(System.err);
            throw error;
        } finally {
            running.set(false);
            progress.interrupt();
            System.err.flush();
        }
    }
    private static void dump(Thread thread, StackTraceElement[] frames) {
        System.err.println("THREAD " + thread.getName() + " " + thread.getState());
        for (int i=0; i<Math.min(frames.length, 16); i++) System.err.println("  at " + frames[i]);
    }
}
