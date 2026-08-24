#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <mach-o/dyld.h>

#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define SERVICE "better-test-credential-broker.v1"
#define MAX_PROFILE 64
#define MAX_SECRET 4096

static void fail(const char *message) {
    fprintf(stderr, "credential-broker: %s\n", message);
    exit(2);
}

static void secure_zero(void *pointer, size_t length) {
    volatile unsigned char *bytes = (volatile unsigned char *)pointer;
    while (length-- > 0) {
        *bytes++ = 0;
    }
}

static void fail_osstatus(const char *operation, OSStatus status) {
    fprintf(stderr, "credential-broker: %s failed (OSStatus=%d)\n",
            operation, (int)status);
    exit(3);
}

static bool valid_profile(const char *profile) {
    size_t length = strlen(profile);
    if (length == 0 || length > MAX_PROFILE) {
        return false;
    }
    for (size_t i = 0; i < length; i++) {
        char c = profile[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.')) {
            return false;
        }
    }
    return true;
}

static void make_key(char *output, size_t output_size, const char *profile,
                     const char *kind) {
    if (!valid_profile(profile)) {
        fail("invalid profile_id");
    }
    int written = snprintf(output, output_size, "%s.%s", profile, kind);
    if (written < 0 || (size_t)written >= output_size) {
        fail("profile key is too long");
    }
}

static OSStatus find_item(const char *account, SecKeychainItemRef *item,
                          void **data, UInt32 *data_length) {
    return SecKeychainFindGenericPassword(
        NULL, (UInt32)strlen(SERVICE), SERVICE, (UInt32)strlen(account),
        account, data_length, data, item);
}

static void upsert_secret(const char *account, const char *value) {
    SecKeychainItemRef item = NULL;
    void *old_data = NULL;
    UInt32 old_length = 0;
    OSStatus status = find_item(account, &item, &old_data, &old_length);
    if (status == errSecSuccess) {
        SecKeychainItemFreeContent(NULL, old_data);
        status = SecKeychainItemModifyAttributesAndData(
            item, NULL, (UInt32)strlen(value), value);
        CFRelease(item);
        if (status != errSecSuccess) {
            fail_osstatus("update keychain item", status);
        }
        return;
    }
    if (status != errSecItemNotFound) {
        fail_osstatus("find keychain item", status);
    }
    status = SecKeychainAddGenericPassword(
        NULL, (UInt32)strlen(SERVICE), SERVICE, (UInt32)strlen(account),
        account, (UInt32)strlen(value), value, NULL);
    if (status != errSecSuccess) {
        fail_osstatus("add keychain item", status);
    }
}

static char *read_secret(const char *account) {
    void *data = NULL;
    UInt32 data_length = 0;
    OSStatus status = find_item(account, NULL, &data, &data_length);
    if (status != errSecSuccess) {
        fail_osstatus("read keychain item", status);
    }
    char *copy = calloc((size_t)data_length + 1, 1);
    if (copy == NULL) {
        SecKeychainItemFreeContent(NULL, data);
        fail("out of memory");
    }
    memcpy(copy, data, data_length);
    SecKeychainItemFreeContent(NULL, data);
    return copy;
}

static bool secret_exists(const char *account) {
    OSStatus status = find_item(account, NULL, NULL, NULL);
    if (status == errSecSuccess) {
        return true;
    }
    if (status == errSecItemNotFound) {
        return false;
    }
    fail_osstatus("check keychain item", status);
    return false;
}

static void delete_secret(const char *account) {
    SecKeychainItemRef item = NULL;
    OSStatus status = find_item(account, &item, NULL, NULL);
    if (status == errSecItemNotFound) {
        return;
    }
    if (status != errSecSuccess) {
        fail_osstatus("find keychain item for deletion", status);
    }
    status = SecKeychainItemDelete(item);
    CFRelease(item);
    if (status != errSecSuccess) {
        fail_osstatus("delete keychain item", status);
    }
}

static void read_tty_line(const char *prompt, char *output, size_t output_size,
                          bool hidden) {
    FILE *tty = fopen("/dev/tty", "r+");
    if (tty == NULL) {
        fail("rotate requires an interactive TTY");
    }
    int fd = fileno(tty);
    struct termios original;
    if (tcgetattr(fd, &original) != 0) {
        fclose(tty);
        fail("cannot read terminal settings");
    }
    struct termios changed = original;
    if (hidden) {
        changed.c_lflag &= ~(ECHO);
        if (tcsetattr(fd, TCSAFLUSH, &changed) != 0) {
            fclose(tty);
            fail("cannot disable terminal echo");
        }
    }
    fprintf(tty, "%s", prompt);
    fflush(tty);
    if (fgets(output, (int)output_size, tty) == NULL) {
        if (hidden) {
            tcsetattr(fd, TCSAFLUSH, &original);
        }
        fclose(tty);
        fail("credential input aborted");
    }
    if (hidden) {
        tcsetattr(fd, TCSAFLUSH, &original);
        fprintf(tty, "\n");
        fflush(tty);
    }
    fclose(tty);
    output[strcspn(output, "\r\n")] = '\0';
    if (output[0] == '\0') {
        fail("credential value must not be empty");
    }
}

static void write_file_exclusive(const char *path, const char *value) {
    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (fd < 0) {
        fail("cannot create lease file");
    }
    size_t length = strlen(value);
    ssize_t written = write(fd, value, length);
    if (written != (ssize_t)length || write(fd, "\n", 1) != 1 ||
        fsync(fd) != 0 || close(fd) != 0) {
        close(fd);
        unlink(path);
        fail("cannot write lease file");
    }
}

static void validate_lease_directory(const char *directory) {
    struct stat info;
    if (lstat(directory, &info) != 0 || !S_ISDIR(info.st_mode)) {
        fail("lease directory does not exist");
    }
    if (info.st_uid != getuid() || (info.st_mode & 077) != 0) {
        fail("lease directory must be owned by the current user with mode 0700");
    }
}

static void command_rotate(const char *profile) {
    char login_account[MAX_SECRET] = {0};
    char login_password[MAX_SECRET] = {0};
    char trade_password[MAX_SECRET] = {0};
    char key[MAX_PROFILE + 32];

    if (!valid_profile(profile)) {
        fail("invalid profile_id");
    }
    read_tty_line("Login account: ", login_account, sizeof(login_account), false);
    read_tty_line("Login password: ", login_password, sizeof(login_password), true);
    read_tty_line("Trade password: ", trade_password, sizeof(trade_password), true);

    make_key(key, sizeof(key), profile, "login-account");
    upsert_secret(key, login_account);
    make_key(key, sizeof(key), profile, "login-password");
    upsert_secret(key, login_password);
    make_key(key, sizeof(key), profile, "trade-password");
    upsert_secret(key, trade_password);

    secure_zero(login_account, sizeof(login_account));
    secure_zero(login_password, sizeof(login_password));
    secure_zero(trade_password, sizeof(trade_password));
    printf("{\"profile_id\":\"%s\",\"status\":\"rotated\"}\n", profile);
}

static void command_status(const char *profile) {
    char account_key[MAX_PROFILE + 32];
    char login_key[MAX_PROFILE + 32];
    char trade_key[MAX_PROFILE + 32];
    make_key(account_key, sizeof(account_key), profile, "login-account");
    make_key(login_key, sizeof(login_key), profile, "login-password");
    make_key(trade_key, sizeof(trade_key), profile, "trade-password");
    printf("{\"profile_id\":\"%s\",\"login_account\":%s,"
           "\"login_password\":%s,\"trade_password\":%s}\n",
           profile, secret_exists(account_key) ? "true" : "false",
           secret_exists(login_key) ? "true" : "false",
           secret_exists(trade_key) ? "true" : "false");
}

static void command_materialize_login(const char *profile,
                                      const char *directory) {
    char account_key[MAX_PROFILE + 32];
    char login_key[MAX_PROFILE + 32];
    char account_path[4096];
    char password_path[4096];
    validate_lease_directory(directory);
    make_key(account_key, sizeof(account_key), profile, "login-account");
    make_key(login_key, sizeof(login_key), profile, "login-password");
    char *account = read_secret(account_key);
    char *password = read_secret(login_key);
    if (snprintf(account_path, sizeof(account_path), "%s/login-account", directory) >=
            (int)sizeof(account_path) ||
        snprintf(password_path, sizeof(password_path), "%s/login-password",
                 directory) >= (int)sizeof(password_path)) {
        fail("lease path is too long");
    }
    write_file_exclusive(account_path, account);
    write_file_exclusive(password_path, password);
    secure_zero(account, strlen(account));
    secure_zero(password, strlen(password));
    free(account);
    free(password);
    printf("{\"profile_id\":\"%s\",\"status\":\"materialized\","
           "\"login_account_file\":\"%s\",\"login_password_file\":\"%s\"}\n",
           profile, account_path, password_path);
}

static void command_pipe_trade(const char *profile) {
    char trade_key[MAX_PROFILE + 32];
    make_key(trade_key, sizeof(trade_key), profile, "trade-password");
    char *password = read_secret(trade_key);
    if (fwrite(password, 1, strlen(password), stdout) != strlen(password) ||
        fputc('\n', stdout) == EOF) {
        secure_zero(password, strlen(password));
        free(password);
        fail("cannot write trade password to pipe");
    }
    fflush(stdout);
    secure_zero(password, strlen(password));
    free(password);
}

static void command_cleanup(const char *directory) {
    char account_path[4096];
    char password_path[4096];
    validate_lease_directory(directory);
    snprintf(account_path, sizeof(account_path), "%s/login-account", directory);
    snprintf(password_path, sizeof(password_path), "%s/login-password", directory);
    const char *paths[] = {account_path, password_path};
    for (size_t i = 0; i < 2; i++) {
        int fd = open(paths[i], O_WRONLY | O_NOFOLLOW);
        if (fd >= 0) {
            ftruncate(fd, 0);
            fsync(fd);
            close(fd);
            unlink(paths[i]);
        } else if (errno != ENOENT) {
            fail("cannot clean lease file");
        }
    }
    if (rmdir(directory) != 0) {
        fail("cannot remove lease directory");
    }
    printf("{\"status\":\"cleaned\"}\n");
}

static void self_test_read(const char *profile) {
    char key[MAX_PROFILE + 32];
    const char *kinds[] = {"login-account", "login-password", "trade-password"};
    const char *expected[] = {"synthetic-account", "synthetic-login",
                              "synthetic-trade"};
    for (size_t i = 0; i < 3; i++) {
        make_key(key, sizeof(key), profile, kinds[i]);
        char *value = read_secret(key);
        if (strcmp(value, expected[i]) != 0) {
            secure_zero(value, strlen(value));
            free(value);
            exit(7);
        }
        secure_zero(value, strlen(value));
        free(value);
    }
}

static void executable_path(char *output, size_t output_size) {
    uint32_t size = (uint32_t)output_size;
    if (_NSGetExecutablePath(output, &size) != 0) {
        fail("executable path is too long");
    }
}

static void command_self_test(void) {
    char profile[MAX_PROFILE + 1];
    snprintf(profile, sizeof(profile), "self-test-%ld-%d", (long)time(NULL),
             getpid());
    char key[MAX_PROFILE + 32];
    const char *kinds[] = {"login-account", "login-password", "trade-password"};
    const char *values[] = {"synthetic-account", "synthetic-login",
                            "synthetic-trade"};
    for (size_t i = 0; i < 3; i++) {
        make_key(key, sizeof(key), profile, kinds[i]);
        upsert_secret(key, values[i]);
    }

    char path[4096];
    executable_path(path, sizeof(path));
    pid_t child = fork();
    if (child < 0) {
        fail("cannot fork self-test reader");
    }
    if (child == 0) {
        execl(path, path, "_self-test-read", profile, NULL);
        _exit(8);
    }
    int status = 0;
    if (waitpid(child, &status, 0) < 0 || !WIFEXITED(status) ||
        WEXITSTATUS(status) != 0) {
        fail("cross-process keychain self-test failed");
    }
    for (size_t i = 0; i < 3; i++) {
        make_key(key, sizeof(key), profile, kinds[i]);
        delete_secret(key);
    }
    printf("{\"status\":\"PASS\",\"provider\":\"macos-keychain\","
           "\"cross_process_read\":true}\n");
}

static void usage(const char *program) {
    fprintf(stderr,
            "Usage:\n"
            "  %s rotate <profile_id>\n"
            "  %s status <profile_id>\n"
            "  %s materialize-login <profile_id> <0700-directory>\n"
            "  %s pipe-trade <profile_id>\n"
            "  %s cleanup <0700-directory>\n"
            "  %s self-test\n",
            program, program, program, program, program, program);
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "self-test") == 0) {
        command_self_test();
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "_self-test-read") == 0) {
        self_test_read(argv[2]);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "rotate") == 0) {
        command_rotate(argv[2]);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "status") == 0) {
        command_status(argv[2]);
        return 0;
    }
    if (argc == 4 && strcmp(argv[1], "materialize-login") == 0) {
        command_materialize_login(argv[2], argv[3]);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "pipe-trade") == 0) {
        command_pipe_trade(argv[2]);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "cleanup") == 0) {
        command_cleanup(argv[2]);
        return 0;
    }
    usage(argv[0]);
    return 2;
}
