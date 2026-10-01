/*
 * Graph89 Remastered - TI graphing calculator emulator for iPhone
 * Copyright (C) 2026 JH
 * Based on Graph89, Copyright (C) 2012-2013 Dritan Hashorva.
 *
 * This program is free software: you can redistribute it and/or modify it under the terms of the
 * GNU General Public License as published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version. This program is distributed in the hope that it
 * will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License (LICENSE) for more details.
 */

/* graph89.c - implements graph89.h with the existing wrapper functions (iOS only). */
#include <pthread.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "graph89.h"
#include "wrappercommon.h"
#include "tiemuwrapper.h"
#include "tilemwrapper.h"
#include "wabbit.h"                 /* TIFILE_t, importvar (wabbitvar.c) */

extern bool is_tilem;                                                          /* wrappercommon.c */
extern void (*graph89_file_received_hook)(const char *path, const char *name);   /* tiemu dbus.c */
extern TIFILE_t *FreeTiFile(TIFILE_t *tifile);                                 /* wabbitvar.c */

static pthread_mutex_t lifecycle_lock = PTHREAD_MUTEX_INITIALIZER;  /* keys vs init/shutdown */
static g89_file_received_fn file_handler;
static void *file_context;
static g89_log_fn log_handler;
static void *log_context;

static bool running(void) { return is_tiemu || is_tilem; }

/* GLib reads the charset from the environment once; the Android app has none set, so it gets ASCII, which decides the
   names of files the calculator sends (Greek letters become _alpha_ ...). The iPhone app and its tests get the same. */
__attribute__((constructor)) static void g89_load(void)
{
    setenv("CHARSET", "ASCII", 1);
}

/* TiEmu's link port (dbus.c recfile) calls this on the engine thread, inside hw_m68k_run. */
static void file_received(const char *path, const char *name)
{
    g89_file_received_fn handler = file_handler;
    if (handler != NULL) handler(file_context, path, name);
    else remove(path);
}

/* Target of ios/Native/shim/android/log.h: LOGI/LOGW/... in the wrapper and TiEmu end up here. */
int __android_log_print(int prio, const char *tag, const char *fmt, ...)
{
    char message[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(message, sizeof message, fmt, ap);
    va_end(ap);
    if (log_handler != NULL) log_handler(log_context, prio, message);
    else fprintf(stderr, "%s: %s\n", tag, message);
    return 0;
}

/* importvar() copies the extension into char[5]: a longer one (or a '.' only in a folder name) overflows. */
static bool short_extension(const char *path)
{
    const char *dot = strrchr(path, '.');
    const char *slash = strrchr(path, '/');
    return dot != NULL && (slash == NULL || dot > slash) && strlen(dot) <= 4;
}

static bool lcd_size_ok(int32_t type, int32_t w, int32_t h)
{
    switch (type) {
    case G89_CALC_TI89: case G89_CALC_TI89T:                        return w == 160 && h == 100;
    case G89_CALC_TI92: case G89_CALC_TI92PLUS: case G89_CALC_V200: return w == 240 && h == 128;
    default:                                                         return w == 96 && h == 64;
    }
}

int32_t g89_init(const g89_config *c)
{
    if (c->calc_type < G89_CALC_TI89 || c->calc_type > G89_CALC_TI83) return G89_E_BAD_ARGUMENT;
    if (!lcd_size_ok(c->calc_type, c->lcd_width, c->lcd_height)) return G89_E_BAD_ARGUMENT;
    if (c->zoom < 1 || (c->grid && c->zoom < 2) || !(c->speed > 0.0)) return G89_E_BAD_ARGUMENT;
    if (c->calc_type <= G89_CALC_TI92PLUS && (c->tmp_dir == NULL || c->tmp_dir[0] == '\0'))
        return G89_E_BAD_ARGUMENT;                     /* tiemu_set_tmp_dir would strlen(NULL) */

    pthread_mutex_lock(&lifecycle_lock);
    graph89_file_received_hook = file_received;        /* JNI re-armed it on every RunEngine/UploadFile */
    graph89_init_commons(c->calc_type, c->lcd_width, c->lcd_height, c->zoom, c->grayscale, c->grid,
                         c->pixel_on, c->pixel_off, c->grid_color, c->speed,
                         c->tmp_dir != NULL ? c->tmp_dir : "");
    /* only TiEmu models set libtifiles' TMP_DIR; .tig handling must never see it NULL */
    if (!is_tiemu && c->tmp_dir != NULL && c->tmp_dir[0] != 0) tiemu_set_tmp_dir(c->tmp_dir);
    pthread_mutex_unlock(&lifecycle_lock);
    return G89_OK;
}

void g89_shutdown(void)
{
    pthread_mutex_lock(&lifecycle_lock);
    graph89_clean_commons();
    pthread_mutex_unlock(&lifecycle_lock);
}

int32_t g89_engine(void)
{
    return is_tiemu ? G89_ENGINE_TIEMU : is_tilem ? G89_ENGINE_TILEM : G89_ENGINE_NONE;
}

int32_t g89_load_image(const char *image_path, int32_t *failed_stage)
{
    int code;
    if (failed_stage != NULL) *failed_stage = 0;
    if (is_tiemu) {
        tiemu_step1_load_defaultconfig();
        if ((code = tiemu_step2_load_image(image_path)) != 0) {
            if (failed_stage != NULL) *failed_stage = G89_STAGE_LOAD_IMAGE;
            return code;
        }
        if ((code = tiemu_step3_init()) != 0) {
            if (failed_stage != NULL) *failed_stage = G89_STAGE_INIT;
            return code;
        }
        tiemu_step4_reset();                            /* always 0; ignored as on Android */
        return G89_OK;
    }
    if (is_tilem) {
        code = tilem_load_image(image_path);
        if (code != 0 && failed_stage != NULL) *failed_stage = G89_STAGE_LOAD_IMAGE;
        return code;
    }
    return G89_E_NOT_RUNNING;
}

int32_t g89_load_state(const char *state_path)
{
    if (is_tiemu) return tiemu_load_state(state_path);
    if (is_tilem) return tilem_load_state(state_path);
    return G89_E_NOT_RUNNING;
}

int32_t g89_save_state(const char *image_path, const char *state_path)
{
    if (is_tiemu) return tiemu_save_state(state_path);
    if (is_tilem) return tilem_save_state(image_path, state_path);
    return G89_E_NOT_RUNNING;
}

void g89_turn_screen_on(void)
{
    if (is_tiemu) tiemu_turn_screen_ON();
    else if (is_tilem) tilem_turn_screen_ON();
}

void g89_run_slice(void)
{
    if (is_tiemu) tiemu_run_engine();
    else if (is_tilem) tilem_run_engine();
}

int32_t g89_reset(void)
{
    if (is_tiemu) return tiemu_step4_reset();
    if (is_tilem) return tilem_reset();
    return G89_E_NOT_RUNNING;
}

void g89_sync_clock(void)
{
    if (is_tiemu) tiemu_sync_clock();
    else if (is_tilem) tilem_sync_clock();
}

int32_t g89_send_file(const char *path)
{
    if (!running()) return G89_E_NOT_RUNNING;
    if (!short_extension(path)) return G89_E_BAD_FILE;
    if (is_tiemu) return tiemu_upload_file(path);

    int type = graph89_emulator_params.calc_type;
    if (type == G89_CALC_TI84PLUS_SE || type == G89_CALC_TI84PLUS || type == G89_CALC_TI83PLUS_SE) {
        TIFILE_t *probe = importvar(path, 0);           /* tilem_send_file dereferences it unchecked */
        if (probe == NULL) return G89_E_BAD_FILE;
        FreeTiFile(probe);
    }
    return tilem_send_file(path);
}

void g89_set_speed(double speed)
{
    if (speed > 0.0) graph89_emulator_params.speed_coefficient = speed;
}

void g89_get_screen_size(int32_t *width, int32_t *height, int32_t *zoom)
{
    bool on = running();
    if (width != NULL)  *width  = on ? graph89_emulator_params.display_buffer_not_zoomed.width : 0;
    if (height != NULL) *height = on ? graph89_emulator_params.display_buffer_not_zoomed.height : 0;
    if (zoom != NULL)   *zoom   = on ? graph89_emulator_params.screen_zoom : 0;
}

int32_t g89_set_zoom(int32_t zoom)
{
    if (!running()) return G89_E_NOT_RUNNING;
    if (zoom < 1 || (graph89_emulator_params.is_grid && zoom < 2)) return G89_E_BAD_ARGUMENT;
    graph89_update_screen_zoom(zoom);
    return G89_OK;
}

uint32_t g89_read_screen(g89_screen_status *status)
{
    uint8_t flags[6] = {0};             /* Android passed ByteArray(6); [0] off, [1] busy */
    uint32_t crc = 0;
    if (running()) crc = (uint32_t)graph89_read_emulated_screen(flags);
    else flags[0] = 1;                  /* the C function has no return value without an engine */
    status->screen_off = flags[0] != 0;
    status->busy = flags[1] != 0;
    return crc;
}

int32_t g89_get_screen(uint32_t *pixels, int32_t pixel_count)
{
    if (!running()) return G89_E_NOT_RUNNING;
    const display_buffer_struct *d = &graph89_emulator_params.display_buffer_not_zoomed;
    int zoom = graph89_emulator_params.screen_zoom;
    if (pixel_count != d->width * d->height * zoom * zoom) return G89_E_BUFFER_SIZE;  /* C would silently skip */
    graph89_get_emulated_screen(pixels, pixel_count);
    return G89_OK;
}

static bool key_ok(int code)
{
    return is_tiemu ? (code >= 0 && code < G89_TIEMU_KEY_COUNT) : (code >= 1 && code <= 64);
}

void g89_send_key(int32_t key, bool pressed)
{
    pthread_mutex_lock(&lifecycle_lock);
    if (running() && key_ok(key)) graph89_send_key(key, pressed ? 1 : 0);
    pthread_mutex_unlock(&lifecycle_lock);
}

void g89_send_keys(const int32_t *keys, int32_t count)
{
    int valid[32];
    int n = 0;
    for (int32_t i = 0; i < count && n < 32; ++i) {
        int k = keys[i];
        if (k < 0 || k >= G89_KEYS_SKIP) continue;
        if (key_ok(k & 0x7F)) valid[n++] = k;
    }
    pthread_mutex_lock(&lifecycle_lock);
    if (running() && n > 0) graph89_send_keys(valid, n);
    pthread_mutex_unlock(&lifecycle_lock);
}

void g89_set_file_received_handler(g89_file_received_fn handler, void *context)
{
    file_context = context;
    file_handler = handler;
}

void g89_set_log_handler(g89_log_fn handler, void *context)
{
    log_context = context;
    log_handler = handler;
}

int32_t g89_install_rom(const char *source_path, const char *image_path, int32_t calc_type, bool is_rom_dump)
{
    if (running()) return G89_E_BUSY;   /* TilEm OS install frees/replaces the global emulator */
    if (!is_rom_dump && !short_extension(source_path)) return G89_E_BAD_FILE;
    return graph89_install_rom(source_path, image_path, calc_type, is_rom_dump ? 1 : 0);
}
