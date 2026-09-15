using System;
using System.Runtime.InteropServices;

public static class FirstInstallWindow
{
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);
    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out int value, int size);

    public static int Apply(IntPtr window)
    {
        int dark = 1;
        DwmSetWindowAttribute(window, 20, ref dark, 4);
        int border = unchecked((int)0xFFFFFFFE);
        DwmSetWindowAttribute(window, 34, ref border, 4);
        int round = 2;
        return DwmSetWindowAttribute(window, 33, ref round, 4);
    }

    public static int ReadCornerPreference(IntPtr window)
    {
        int value;
        return DwmGetWindowAttribute(window, 33, out value, 4) == 0 ? value : -1;
    }
}
