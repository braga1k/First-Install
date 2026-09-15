using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("First Install")]
[assembly: AssemblyDescription("First Install - Windows app installer")]
[assembly: AssemblyProduct("First Install")]
[assembly: AssemblyVersion("2.7.0.0")]
[assembly: AssemblyFileVersion("2.7.0.0")]

internal static class Launcher
{
    [STAThread]
    private static int Main(string[] args)
    {
        bool test = args.Length == 1 && (args[0] == "--smoke-test" || args[0] == "--self-test");
        string folder = Path.Combine(Path.GetTempPath(), "FirstInstall-" + Guid.NewGuid().ToString("N"));
        string output = "";
        try
        {
            if (args.Length > 0 && !test) throw new ArgumentException("Unknown argument.");
            Directory.CreateDirectory(folder);
            string script = Path.Combine(folder, "FirstInstall.ps1");
            using (Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("FirstInstall.Payload"))
            using (FileStream file = File.Create(script)) resource.CopyTo(file);
            string exe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            ProcessStartInfo start = new ProcessStartInfo(exe,
                "-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File \"" + script + "\"" +
                (test ? (args[0] == "--smoke-test" ? " -SmokeTest" : " -SelfTest") : ""));
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.RedirectStandardOutput = true;
            start.RedirectStandardError = true;
            using (Process child = new Process())
            {
                child.StartInfo = start;
                object gate = new object();
                DataReceivedEventHandler collect = delegate(object sender, DataReceivedEventArgs e) {
                    if (e.Data != null) lock (gate) output += e.Data + Environment.NewLine;
                };
                child.OutputDataReceived += collect;
                child.ErrorDataReceived += collect;
                child.Start();
                child.BeginOutputReadLine();
                child.BeginErrorReadLine();
                child.WaitForExit();
                if (child.ExitCode != 0) throw new Exception(output.Length > 0 ? output : "PowerShell exited with code " + child.ExitCode);
            }
            if (test) File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, args[0].Substring(2) + ".log"), output);
            return 0;
        }
        catch (Exception error)
        {
            string log = Path.Combine(test ? AppDomain.CurrentDomain.BaseDirectory : Path.GetTempPath(), "FirstInstall-startup-error.log");
            try { File.WriteAllText(log, error.ToString()); } catch { }
            if (!test) MessageBox.Show("Could not start First Install.\n\n" + error.Message + "\n\nLog: " + log, "First Install", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            try { if (Directory.Exists(folder)) Directory.Delete(folder, true); } catch { }
        }
    }
}
