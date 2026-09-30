/*
 *   Graph89 - Emulator for Android
 *
 *	 Copyright (C) 2012-2013  Dritan Hashorva
 *
 *   This program is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.

 *   You should have received a copy of the GNU General Public License
 *   along with this program.  If not, see <http://www.gnu.org/licenses/>
 */


#include <jni.h>
#include <stdio.h>
#include <wrappercommon.h>
#include <tiemuwrapper.h>
#include <androidlog.h>

/* Owned by the link port (dbus.c in TiEmu); set here before the engine runs. */
extern void (*graph89_file_received_hook)(const char * path, const char * name);

/* The engine thread's JNIEnv while it runs the engine or sends a file: the calculator sends files meanwhile. */
static JNIEnv * engine_env = NULL;

/*
 * Called by the link port (dbus.c) when the calculator has sent a file: [path] holds it, [name] is the file name
 * made from the variable's name and type. Hands both to EmulatorCore.onFileReceived, which moves the file away.
 */
static void file_received(const char * path, const char * name)
{
	JNIEnv * env = engine_env;
	if (env == NULL)
	{
		remove(path);
		return;
	}

	jclass cls = (*env)->FindClass(env, "com/example/calc89/core/EmulatorCore");
	jmethodID method = cls != NULL ? (*env)->GetStaticMethodID(env, cls, "onFileReceived", "(Ljava/lang/String;Ljava/lang/String;)V") : NULL;
	if (method == NULL)
	{
		(*env)->ExceptionClear(env);
		remove(path);
		return;
	}

	jstring jPath = (*env)->NewStringUTF(env, path);
	jstring jName = (*env)->NewStringUTF(env, name);
	(*env)->CallStaticVoidMethod(env, cls, method, jPath, jName);
	if ((*env)->ExceptionCheck(env)) (*env)->ExceptionClear(env);

	(*env)->DeleteLocalRef(env, jPath);
	(*env)->DeleteLocalRef(env, jName);
	(*env)->DeleteLocalRef(env, cls);
}

JNIEXPORT void JNICALL Java_com_example_calc89_core_EmulatorCore_nativeTiEmuStep1LoadDefaultConfig(JNIEnv * env, jobject obj)
{
	tiemu_step1_load_defaultconfig();
	LOGI("TiEmu LoadDefaultConfig");
}

JNIEXPORT jint JNICALL Java_com_example_calc89_core_EmulatorCore_nativeTiEmuStep2LoadImage(JNIEnv * env, jobject obj, jstring image_file)
{
	const char * filename = (*env)->GetStringUTFChars(env, image_file, 0);
	int code = tiemu_step2_load_image(filename);
	(*env)->ReleaseStringUTFChars(env, image_file, filename);
	LOGI("TiEmu LoadImage %d", code);
	return (jint)code;
}

JNIEXPORT jint JNICALL Java_com_example_calc89_core_EmulatorCore_nativeTiEmuStep3Init(JNIEnv * env, jobject obj)
{
	int code = tiemu_step3_init();
	LOGI("TiEmu Init %d", code);
	return (jint)code;
}

JNIEXPORT jint JNICALL Java_com_example_calc89_core_EmulatorCore_nativeTiEmuStep4Reset (JNIEnv * env, jobject obj)
{
	int code = tiemu_step4_reset();
	LOGI("TiEmu Reset %d", code);
	return (jint)code;
}

JNIEXPORT jint JNICALL Java_com_example_calc89_core_EmulatorCore_nativeTiEmuSaveState(JNIEnv * env, jobject obj, jstring state_file)
{
	const char* filename = (*env)->GetStringUTFChars(env, state_file, 0);
	int code = tiemu_save_state(filename);
	(*env)->ReleaseStringUTFChars(env, state_file, filename);
	LOGI("SaveState %d", code);
	return (jint)code;
}

JNIEXPORT void JNICALL Java_com_example_calc89_core_EmulatorCore_nativeTiEmuTurnScreenOn(JNIEnv * env, jobject obj)
{
	tiemu_turn_screen_ON();
	LOGI("TiEmu Turn Screen ON");
}

JNIEXPORT jint JNICALL Java_com_example_calc89_core_EmulatorCore_nativeTiEmuLoadState(JNIEnv * env, jobject obj, jstring str)
{
	const char * filename = (*env)->GetStringUTFChars(env, str, 0);

	int code = tiemu_load_state(filename);

	(*env)->ReleaseStringUTFChars(env, str, filename);
	LOGI("TiEmu LoadState %d", code);

	return (jint)code;
}

JNIEXPORT void JNICALL Java_com_example_calc89_core_EmulatorCore_nativeTiEmuSyncClock(JNIEnv * env, jobject obj)
{
	tiemu_sync_clock();
}

JNIEXPORT void JNICALL Java_com_example_calc89_core_EmulatorCore_nativeTiEmuRunEngine(JNIEnv * env, jobject obj)
{
	graph89_file_received_hook = file_received;
	engine_env = env;
	tiemu_run_engine();
	engine_env = NULL;
}

JNIEXPORT jint JNICALL Java_com_example_calc89_core_EmulatorCore_nativeTiEmuUploadFile(JNIEnv * env, jobject obj, jstring str)
{
	const char * filename = (*env)->GetStringUTFChars(env, str, 0);

	graph89_file_received_hook = file_received;
	engine_env = env;
	int code = tiemu_upload_file(filename);
	engine_env = NULL;

	(*env)->ReleaseStringUTFChars(env, str, filename);
	LOGI("TiEmu UploadFile %d", code);

	return (jint)code;
}
