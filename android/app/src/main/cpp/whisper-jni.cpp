#include <jni.h>
#include <android/log.h>
#include <string>
#include "whisper.h"

#define TAG "WhisperJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

extern "C" {

JNIEXPORT jlong JNICALL
Java_it_shek_dictator_app_WhisperLib_initContext(
        JNIEnv *env, jobject /* this */, jstring modelPath) {
    const char *path = env->GetStringUTFChars(modelPath, nullptr);
    LOGI("Loading model from: %s", path);

    struct whisper_context_params cparams = whisper_context_default_params();
    struct whisper_context *ctx = whisper_init_from_file_with_params(path, cparams);

    env->ReleaseStringUTFChars(modelPath, path);

    if (ctx == nullptr) {
        LOGE("Failed to load model");
        return 0;
    }

    LOGI("Model loaded successfully");
    return (jlong) ctx;
}

JNIEXPORT jstring JNICALL
Java_it_shek_dictator_app_WhisperLib_transcribe(
        JNIEnv *env, jobject /* this */, jlong contextPtr, jfloatArray audioData) {
    auto *ctx = (struct whisper_context *) contextPtr;
    if (ctx == nullptr) {
        return env->NewStringUTF("");
    }

    jsize numSamples = env->GetArrayLength(audioData);
    jfloat *samples = env->GetFloatArrayElements(audioData, nullptr);

    LOGI("Transcribing %d samples (%.1fs)", numSamples, numSamples / 16000.0f);

    struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_progress = false;
    params.print_special = false;
    params.print_timestamps = false;
    params.print_realtime = false;
    params.translate = false;
    params.language = "en";
    params.n_threads = 4;
    params.no_context = true;
    params.single_segment = false;

    int result = whisper_full(ctx, params, samples, numSamples);

    env->ReleaseFloatArrayElements(audioData, samples, 0);

    if (result != 0) {
        LOGE("Transcription failed with code %d", result);
        return env->NewStringUTF("");
    }

    std::string text;
    int nSegments = whisper_full_n_segments(ctx);
    for (int i = 0; i < nSegments; i++) {
        const char *segText = whisper_full_get_segment_text(ctx, i);
        if (segText != nullptr) {
            text += segText;
        }
    }

    // Trim leading/trailing whitespace
    size_t start = text.find_first_not_of(" \t\n\r");
    size_t end = text.find_last_not_of(" \t\n\r");
    if (start != std::string::npos) {
        text = text.substr(start, end - start + 1);
    } else {
        text = "";
    }

    LOGI("Transcription result: %s", text.c_str());
    return env->NewStringUTF(text.c_str());
}

JNIEXPORT void JNICALL
Java_it_shek_dictator_app_WhisperLib_freeContext(
        JNIEnv *env, jobject /* this */, jlong contextPtr) {
    auto *ctx = (struct whisper_context *) contextPtr;
    if (ctx != nullptr) {
        whisper_free(ctx);
        LOGI("Context freed");
    }
}

}
