// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.


// Keeps every preference a Swift test saves out of the developer's real
// ~/Library/Preferences.
//
// Tests open UserDefaults suites with made-up names. The preferences daemon
// (cfprefsd) saves each one as a plist in the account's real preferences
// folder, and taking the domain away again leaves the file behind, empty. On
// 2026-11-02 some 56,000 of them had stopped macOS saving any app's settings.
// Moving the test's home does not help: cfprefsd ignores CFFIXED_USER_HOME and
// saves to the real folder anyway (TestPreferencesTests found this out).
//
// What cfprefsd does honour is a container, the folder a sandboxed app's
// preferences live in. So before main this points UserDefaults at a container
// under the test's own temporary directory:
//
//   - every suite a test opens, `UserDefaults(suiteName:)`, is opened in it;
//   - `UserDefaults.standard`, which would otherwise save under the test
//     program's own name, is one more suite in it;
//   - `persistentDomain(forName:)` reads a domain from it.
//
// Only the system's domains, the global one (NSGlobalDomain) and Apple's
// (com.apple.*), which the frameworks read and tests only read, are left
// alone. The container's path is in
// SWIFT_TEST_PREFERENCES_CONTAINER for the tests' ScratchDefaults helper. Bazel throws the container away with the rest of
// TEST_TMPDIR. The container initializer is Apple's own but not public; if a
// macOS release drops it the test stops here, loudly, rather than running on
// and saving into the real folder.

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef id (*alloc_fn)(id, SEL);
typedef id (*init_suite_fn)(id, SEL, id);
typedef id (*init_container_fn)(id, SEL, id, id);
typedef id (*url_fn)(id, SEL, id, BOOL);
typedef id (*string_fn)(id, SEL, const char *);

static SEL container_init;
static IMP original_init_with_suite;
static id container_url;   // NSURL, kept for the life of the process
static id standard_suite;  // NSUserDefaults, made on first use
static pthread_mutex_t standard_lock = PTHREAD_MUTEX_INITIALIZER;
static IMP original_persistent_domain;
static CFStringRef container_path;
// CoreFoundation's own reader for a domain in a container: the container
// initializer saves there, but `persistentDomain(forName:)` would look in
// the real folder and find nothing.
typedef CFDictionaryRef (*copy_multiple_fn)(CFArrayRef, CFStringRef, CFStringRef, CFStringRef, CFStringRef);
static copy_multiple_fn copy_multiple_in_container;

static void give_up(const char *why) {
    fprintf(stderr, "swift-test-preferences: %s; not running the test, so it cannot save into "
                    "~/Library/Preferences\n", why);
    _exit(70);
}

static int make_folder(const char *path) {
    return mkdir(path, 0700) == 0 || errno == EEXIST ? 0 : -1;
}

static id ns_string(const char *text) {
    return ((string_fn)objc_msgSend)((id)objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"), text);
}

static id open_in_container(id self, id name) {
    return ((init_container_fn)objc_msgSend)(self, container_init, name, container_url);
}

// Domains the system owns: the global one, and Apple's own (com.apple.*),
// which the frameworks read through suites of their own and tests only read.
static int is_system_domain(id name) {
    CFStringRef domain = (CFStringRef)name;
    return CFEqual(domain, CFSTR("NSGlobalDomain")) || CFEqual(domain, kCFPreferencesAnyApplication) ||
           CFStringHasPrefix(domain, CFSTR("com.apple."));
}

static id redirected_init_with_suite(id self, SEL cmd, id name) {
    if (name == nil || is_system_domain(name)) {
        return ((init_suite_fn)original_init_with_suite)(self, cmd, name);
    }
    return open_in_container(self, name);
}

typedef id (*persistent_domain_fn)(id, SEL, id);

static id redirected_persistent_domain(id self, SEL cmd, id name) {
    if (name == nil || is_system_domain(name)) {
        return ((persistent_domain_fn)original_persistent_domain)(self, cmd, name);
    }
    CFDictionaryRef values = copy_multiple_in_container(NULL, (CFStringRef)name, kCFPreferencesCurrentUser,
                                                        kCFPreferencesAnyHost, container_path);
    if (values == NULL) {
        return nil;
    }
    // A domain with nothing saved reads as missing, as it does in the real folder.
    if (CFDictionaryGetCount(values) == 0) {
        CFRelease(values);
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)((id)values, sel_registerName("autorelease"));
}

static id redirected_standard(id cls, SEL cmd) {
    (void)cmd;
    // The test program's own domain, as `standard` would use, but in the
    // container, made once whichever thread asks first.
    pthread_mutex_lock(&standard_lock);
    if (standard_suite == nil) {
        id allocated = ((alloc_fn)objc_msgSend)(cls, sel_registerName("alloc"));
        char name[256];
        snprintf(name, sizeof name, "%s", getprogname());
        standard_suite = open_in_container(allocated, ns_string(name));
    }
    pthread_mutex_unlock(&standard_lock);
    return standard_suite;
}

__attribute__((constructor)) static void vitruvian_test_preferences(void) {
    // Under `bazel test` the container goes in TEST_TMPDIR; a test program
    // started by hand gets one in the temporary directory. Its name is new
    // for every run: cfprefsd remembers a container's domains by path, even
    // after Bazel deletes the folder, and would hand a later run of the same
    // test what the last one saved.
    char base[PATH_MAX];
    const char *test_tmpdir = getenv("TEST_TMPDIR");
    const char *tmpdir = getenv("TMPDIR");
    const char *parent = test_tmpdir != NULL && test_tmpdir[0] != '\0' ? test_tmpdir
                         : tmpdir != NULL && tmpdir[0] != '\0'         ? tmpdir
                                                                        : "/tmp";
    if (snprintf(base, sizeof base, "%s/preferences-container.XXXXXX", parent) >= (int)sizeof base ||
        mkdtemp(base) == NULL) {
        give_up("could not make the preferences container");
    }
    char library[PATH_MAX], preferences[PATH_MAX];
    if (snprintf(library, sizeof library, "%s/Library", base) >= (int)sizeof library ||
        snprintf(preferences, sizeof preferences, "%s/Preferences", library) >= (int)sizeof preferences ||
        make_folder(library) != 0 || make_folder(preferences) != 0) {
        give_up("could not make the container's Library/Preferences folder");
    }

    Class defaults = objc_getClass("NSUserDefaults");
    container_init = sel_registerName("_initWithSuiteName:container:");
    Method init_with_suite = class_getInstanceMethod(defaults, sel_registerName("initWithSuiteName:"));
    Method standard = class_getClassMethod(defaults, sel_registerName("standardUserDefaults"));
    Method persistent_domain = class_getInstanceMethod(defaults, sel_registerName("persistentDomainForName:"));
    copy_multiple_in_container =
        (copy_multiple_fn)dlsym(RTLD_DEFAULT, "_CFPreferencesCopyMultipleWithContainer");
    if (defaults == Nil || init_with_suite == NULL || standard == NULL || persistent_domain == NULL ||
        copy_multiple_in_container == NULL || !class_respondsToSelector(defaults, container_init)) {
        give_up("this macOS has no UserDefaults container initializer to keep test preferences apart");
    }

    // ScratchDefaults, the tests' own helper, opens its suites here too.
    if (setenv("SWIFT_TEST_PREFERENCES_CONTAINER", base, 1) != 0) {
        give_up("could not publish the preferences container");
    }
    container_url = ((url_fn)objc_msgSend)((id)objc_getClass("NSURL"),
                                           sel_registerName("fileURLWithPath:isDirectory:"),
                                           ns_string(base), YES);
    CFRetain((CFTypeRef)container_url);
    container_path = CFStringCreateWithCString(NULL, base, kCFStringEncodingUTF8);
    original_init_with_suite = method_setImplementation(init_with_suite, (IMP)redirected_init_with_suite);
    method_setImplementation(standard, (IMP)redirected_standard);
    original_persistent_domain = method_setImplementation(persistent_domain, (IMP)redirected_persistent_domain);
}
