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

/* Lets tiemu-3.03/src/androidlog.h (LOGI/LOGW/...) compile on iOS unchanged; implemented in graph89.c. */
#ifndef G89_ANDROID_LOG_SHIM_H
#define G89_ANDROID_LOG_SHIM_H
typedef enum android_LogPriority {
    ANDROID_LOG_UNKNOWN = 0, ANDROID_LOG_DEFAULT, ANDROID_LOG_VERBOSE, ANDROID_LOG_DEBUG,
    ANDROID_LOG_INFO, ANDROID_LOG_WARN, ANDROID_LOG_ERROR, ANDROID_LOG_FATAL, ANDROID_LOG_SILENT
} android_LogPriority;
int __android_log_print(int prio, const char *tag, const char *fmt, ...);
#endif
