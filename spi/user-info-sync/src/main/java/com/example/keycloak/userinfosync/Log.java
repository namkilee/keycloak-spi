package com.example.keycloak.userinfosync;

public final class Log {
  private Log() {}

  public static void info(String msg) {
    System.out.println("[userinfosync][INFO] " + msg);
  }

  public static void warn(String msg) {
    System.out.println("[userinfosync][WARN] " + msg);
  }

  public static void error(String msg, Throwable t) {
    System.out.println("[userinfosync][ERROR] " + msg);
    if (t != null) {
      t.printStackTrace(System.out);
    }
  }
}
