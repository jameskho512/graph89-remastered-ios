/*
 * graph89.h - plain C API of the Graph89 native core (TiEmu 3.03, TilEm 2.0) for the iOS app.
 *
 * Replaces the JNI layer (wrapper/wrappercommonjni.c, tiemuwrapperjni.c, tilemwrapperjni.c).
 * Implemented by ios/Native/graph89.c on top of the unchanged wrapper sources.
 * Graph89 Remastered, Copyright (C) 2026 JH; based on Graph89 (C) 2012-2013 Dritan Hashorva.
 * GNU General Public License v3 or later.
 *
 * ONE emulator per process: the cores keep all their state in globals.
 *
 * Thread rules (the Android app's model):
 *   [engine]  only from the single engine thread, one call at a time.
 *   [screen]  g89_set_zoom / g89_read_screen / g89_get_screen: on the engine thread between slices
 *             (race-free), or on one separate poll thread concurrently with [engine] calls (what Android
 *             does: emulator memory is read without a lock). Stop the poll thread before g89_shutdown.
 *   [any]     any thread (keys). Serialised against g89_init / g89_shutdown by an internal lock;
 *             NOT against g89_run_slice (unlocked writes, as on Android).
 *   [idle]    only while no engine is initialised and no other g89_ call is running.
 * Paths are NUL-terminated UTF-8 and only need to stay valid for the duration of the call.
 */
#ifndef GRAPH89_H
#define GRAPH89_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__clang__)
#pragma clang assume_nonnull begin
#define G89_NULLABLE _Nullable
#else
#define G89_NULLABLE
#endif

/* Calculator types: identical to CALC_TYPE_* (wrappercommon.h) and CalcModel.type (Kotlin). */
#define G89_CALC_TI89          1
#define G89_CALC_TI89T         2
#define G89_CALC_V200          3
#define G89_CALC_TI92          4
#define G89_CALC_TI92PLUS      5
#define G89_CALC_TI84PLUS_SE   6
#define G89_CALC_TI84PLUS      7
#define G89_CALC_TI83PLUS_SE   8
#define G89_CALC_TI83PLUS      9
#define G89_CALC_TI83         10

/* Engines (g89_engine). Types 1-5 run on TiEmu, 6-10 on TilEm. */
#define G89_ENGINE_NONE        0
#define G89_ENGINE_TIEMU       1
#define G89_ENGINE_TILEM       2

/* LCD sizes in pixels; g89_config.lcd_width/lcd_height must match the model. */
#define G89_LCD_TI89_W       160   /* TI-89, TI-89 Titanium */
#define G89_LCD_TI89_H       100
#define G89_LCD_TI92_W       240   /* TI-92, TI-92 Plus, Voyage 200 */
#define G89_LCD_TI92_H       128
#define G89_LCD_TI83_W        96   /* TI-83 ... TI-84 Plus SE */
#define G89_LCD_TI83_H        64

/* Key codes. TiEmu: TiKey enum index (tiemu-3.03/src/core/ti_hw/keydefs.h), 0..84.
   TilEm: scancode (tilem-2.0/emu/scancodes.h), 1..64. Per-key values: assets/skin/ti89.json, ti84.json. */
#define G89_TIEMU_KEY_2ND       7
#define G89_TIEMU_KEY_ON       78
#define G89_TIEMU_KEY_ALPHA    79   /* press/release are counted: keep them balanced */
#define G89_TIEMU_KEY_COUNT    85
#define G89_TILEM_KEY_ON     0x29
#define G89_TILEM_KEY_2ND    0x36

/* g89_send_keys entries */
#define G89_KEYS_RELEASE     0x80   /* code | G89_KEYS_RELEASE releases the key */
#define G89_KEYS_SKIP        0xFF   /* ignored */

/* g89_load_image: which step failed */
#define G89_STAGE_LOAD_IMAGE    2   /* TiEmu Step2 / TilEm load: "The IMG file did not load" */
#define G89_STAGE_INIT          3   /* TiEmu Step3:              "The initialization failed"  */

/* Log priorities passed to the log handler (Android's values). */
#define G89_LOG_DEBUG           3
#define G89_LOG_INFO            4
#define G89_LOG_WARN            5
#define G89_LOG_ERROR           6
#define G89_LOG_FATAL           7

/* Errors produced by this shim. Core codes pass through unchanged:
   TiEmu ERR_* 768-783 (768 CANT_OPEN, 770 INVALID_IMAGE, 772 NO_IMAGE, 775 NOT_TI_FILE, 776 MALLOC,
   780 CANT_OPEN_STATE, 781 REVISION_MATCH, 782 HEADER_MATCH, 783 STATE_MATCH, ...);
   TilEm small values (-1 cannot open, 1 bad/short file, -2 not an OS, -3 OS load failed,
   -3/-4 cannot write, -10 link transfer failed). */
#define G89_OK                  0
#define G89_E_NOT_RUNNING   -1001   /* no engine initialised */
#define G89_E_BAD_ARGUMENT  -1002
#define G89_E_BUFFER_SIZE   -1003   /* pixel_count != width * height * zoom * zoom */
#define G89_E_BAD_FILE      -1004   /* unreadable/unparsable file, or extension longer than ".xyz" */
#define G89_E_BUSY          -1005   /* g89_install_rom while an engine is initialised */

typedef struct g89_config {
    int32_t  calc_type;            /* G89_CALC_* */
    int32_t  lcd_width;            /* G89_LCD_* of the model */
    int32_t  lcd_height;
    int32_t  zoom;                 /* integer scale of g89_get_screen output, >= 1 (>= 2 with grid) */
    bool     grayscale;            /* grayscale LCD emulation */
    bool     grid;                 /* dot-matrix grid overlay (Android: false) */
    uint32_t pixel_on;             /* 0xAARRGGBB, alpha 0xFF */
    uint32_t pixel_off;
    uint32_t grid_color;           /* Android passes pixel_off */
    double   speed;                /* CPU speed coefficient, 1.0 = 100 %; > 0 */
    const char *G89_NULLABLE tmp_dir; /* writable folder, no trailing '/'; required for TiEmu
                                         (received files land in <tmp_dir>/file.rec); copied */
} g89_config;

typedef struct g89_screen_status {
    bool screen_off;               /* LCD off (calculator off) */
    bool busy;                     /* busy indicator lit (never set for TilEm in grayscale) */
} g89_screen_status;

/* A file the calculator sent (TiEmu models only). Called synchronously on the engine thread from inside
   g89_run_slice (emulation is paused meanwhile). [path] is reused for the next file: move or copy it
   before returning. [name] is a bare file name such as "prog1.89p" or "group.89g"; it may contain '/'
   or start with '.', so clean it up. Both strings are valid only during the call.
   Do not call any g89_ function from inside the handler. */
typedef void (*g89_file_received_fn)(void *G89_NULLABLE context, const char *path, const char *name);

/* One formatted log line from the wrapper or TiEmu (LOGI/LOGW/...). May be called on any thread. */
typedef void (*g89_log_fn)(void *G89_NULLABLE context, int32_t priority, const char *message);

/* ---- lifecycle [engine] ---- */

/* Sets up the engine for config->calc_type (cleans up any previous one first). Replaces
   nativeInitGraph89. Returns G89_OK or G89_E_BAD_ARGUMENT. */
int32_t g89_init(const g89_config *config);

/* Frees everything (TiEmu exit, TilEm free, display buffer). Safe when nothing is initialised.
   Call after the last [engine]/[screen] call has returned. Replaces nativeCleanGraph89. */
void g89_shutdown(void);

/* G89_ENGINE_* currently initialised. [any] */
int32_t g89_engine(void);

/* Loads the ROM image. TiEmu: Step1 default config, Step2 load image, Step3 init, Step4 reset.
   TilEm: load the ROM and reset. On failure *failed_stage (optional) gets G89_STAGE_*.
   Returns 0 or the core's error. */
int32_t g89_load_image(const char *image_path, int32_t *G89_NULLABLE failed_stage);

/* Restores a saved state; call after g89_load_image, and only if the file exists (the Android app
   skips the call otherwise). Non-zero: the state is unusable (offer to discard it). */
int32_t g89_load_state(const char *state_path);

/* Saves the state. TilEm also rewrites [image_path] with the whole flash (archive); pass the same image
   that was loaded. TiEmu ignores image_path. Android saves only after more than 20 loop iterations. */
int32_t g89_save_state(const char *image_path, const char *state_path);

/* Wakes the calculator after load: TiEmu raises the ON interrupt; TilEm runs ~10M clocks with ON
   pressed in the middle (blocks noticeably). */
void g89_turn_screen_on(void);

/* One engine-loop slice of emulated CPU time scaled by the speed coefficient (TiEmu >= 30 ms emulated,
   TilEm 700000 clocks). May call the file-received handler. */
void g89_run_slice(void);

/* The settings "Reset". TiEmu: hardware reset. TilEm 83+/84+: erases the archive, rewrites the image
   file, resets; TI-83: does nothing. Returns 0, or -4 (TilEm, image not writable). */
int32_t g89_reset(void);

/* Sets the calculator clock to the device's local time over the emulated link (errors ignored;
   the TI-83/83+ have no clock). Android does it once a second after a new ROM's first start, or on request. */
void g89_sync_clock(void);

/* Sends a file over the emulated link; blocks while the calculator receives it.
   TiEmu: 775 if not a TI-89/92/V200 file, otherwise 0 (transfer errors are not reported, and a calculator
   that stops reading can hang the call). TilEm: 0, -4, -10, or G89_E_BAD_FILE. */
int32_t g89_send_file(const char *path);

/* Changes the speed coefficient for the next slices (> 0). */
void g89_set_speed(double speed);

/* ---- screen [screen] ---- */

/* Unscaled LCD size and current zoom (0s when no engine). */
void g89_get_screen_size(int32_t *G89_NULLABLE width, int32_t *G89_NULLABLE height, int32_t *G89_NULLABLE zoom);

/* Changes the integer zoom of g89_get_screen. Returns G89_OK, G89_E_BAD_ARGUMENT or G89_E_NOT_RUNNING. */
int32_t g89_set_zoom(int32_t zoom);

/* Refreshes the internal unscaled frame from emulator memory and fills *status. Returns a checksum of the
   frame: fetch pixels when it changed (Android also fetches every 40th poll; TiEmu grayscale returns 0
   when the LCD did not change, TiEmu screen off returns 0xFFFFFFFF). Call at least once before
   g89_get_screen. With no engine: returns 0, screen_off = true. */
uint32_t g89_read_screen(g89_screen_status *status);

/* Copies the last frame, scaled by the integer zoom (nearest neighbour), into [pixels]:
   (width*zoom) x (height*zoom) uint32 0xAARRGGBB, row-major, top-left first
   (CoreGraphics: noneSkipFirst | byteOrder32Little). [pixel_count] must be width*height*zoom*zoom. */
int32_t g89_get_screen(uint32_t *pixels, int32_t pixel_count);

/* ---- keys [any] ---- */

/* Presses or releases one key (codes above). Invalid codes and calls without an engine are ignored. */
void g89_send_key(int32_t key, bool pressed);

/* Queues a key sequence (up to 32 entries, consumed by the emulated keyboard scan): code = press,
   code | G89_KEYS_RELEASE = release, G89_KEYS_SKIP ignored. Unused by the Android app. */
void g89_send_keys(const int32_t *keys, int32_t count);

/* ---- callbacks (set before g89_init / while stopped) ---- */

void g89_set_file_received_handler(g89_file_received_fn G89_NULLABLE handler, void *G89_NULLABLE context);
void g89_set_log_handler(g89_log_fn G89_NULLABLE handler, void *G89_NULLABLE context);

/* ---- ROM install [idle] ---- */

/* Builds the image file [image_path] from an OS upgrade (.89u/.v2u/.9xu/.8xu, is_rom_dump false) or a ROM
   dump (is_rom_dump true; TiEmu .rom, TilEm raw flash copy). TiEmu ignores calc_type (the file decides).
   Returns 0, the core's error, G89_E_BAD_FILE or G89_E_BUSY. */
int32_t g89_install_rom(const char *source_path, const char *image_path, int32_t calc_type, bool is_rom_dump);

#if defined(__clang__)
#pragma clang assume_nonnull end
#endif

#ifdef __cplusplus
}
#endif

#endif /* GRAPH89_H */
