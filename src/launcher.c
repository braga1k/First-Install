#include <windows.h>
#include <stdio.h>
#include "payload.h"
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR args, int show) {
    (void)instance; (void)previous; (void)args; (void)show;
    WCHAR temp[MAX_PATH], stub[MAX_PATH], script[MAX_PATH + 8];
    WCHAR system[MAX_PATH], exe[MAX_PATH + 80], command[2 * MAX_PATH + 256];
    HANDLE file = INVALID_HANDLE_VALUE;
    DWORD written = 0, code = 1;
    PROCESS_INFORMATION child = {0};
    STARTUPINFOW start = {0}; start.cb = sizeof(start);
    if (!GetTempPathW(MAX_PATH, temp) || !GetTempFileNameW(temp, L"FIS", 0, stub)) goto fail;
    if (swprintf(script, MAX_PATH + 8, L"%ls.ps1", stub) < 0) { DeleteFileW(stub); goto fail; }
    file = CreateFileW(script, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    DeleteFileW(stub);
    if (file == INVALID_HANDLE_VALUE) goto fail;
    if (!WriteFile(file, payload, sizeof(payload), &written, NULL) || written != sizeof(payload) || !FlushFileBuffers(file)) goto cleanup;
    CloseHandle(file); file = INVALID_HANDLE_VALUE;
    if (!GetSystemDirectoryW(system, MAX_PATH)) goto cleanup;
    swprintf(exe, MAX_PATH + 80, L"%ls\\WindowsPowerShell\\v1.0\\powershell.exe", system);
    swprintf(command, 2 * MAX_PATH + 256, L"\"%ls\" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File \"%ls\"", exe, script);
    if (!CreateProcessW(exe, command, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &start, &child)) goto cleanup;
    WaitForSingleObject(child.hProcess, INFINITE);
    GetExitCodeProcess(child.hProcess, &code);
    CloseHandle(child.hThread); CloseHandle(child.hProcess);
cleanup:
    if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
    DeleteFileW(script);
    if (code == 0) return 0;
fail:
    MessageBoxW(NULL, L"Could not start or complete First Install. See the README and logs.", L"First Install", MB_OK | MB_ICONERROR);
    return (int)code;
}
