package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"strings"
	"time"
)

type transcript struct {
	text     string
	language string // ISO 639-1 code, or "auto" when unknown
}

// whisper talks to whisper.cpp's own server (/inference), started with
// --convert so it accepts Ogg/Opus voice messages through ffmpeg.
type whisper struct {
	url      string
	language string // forced language code; "" lets Whisper detect it
	http     *http.Client
}

func newWhisper(cfg config) (*whisper, error) {
	if cfg.whisperURL == "" {
		return nil, errors.New("WHISPER_URL isn't set (the whisper.cpp server's address)")
	}
	return &whisper{
		url:      strings.TrimRight(cfg.whisperURL, "/"),
		language: cfg.language,
		// On a few CPU cores a long voice message can take a while.
		http: &http.Client{Timeout: 30 * time.Minute},
	}, nil
}

func (w *whisper) transcribe(ctx context.Context, audio []byte, filename string) (*transcript, error) {
	language := w.language
	if language == "" {
		language = "auto"
	}
	var body bytes.Buffer
	form := multipart.NewWriter(&body)
	for k, v := range map[string]string{"response_format": "verbose_json", "temperature": "0", "language": language} {
		if err := form.WriteField(k, v); err != nil {
			return nil, err
		}
	}
	part, err := form.CreateFormFile("file", filename)
	if err != nil {
		return nil, err
	}
	if _, err = part.Write(audio); err != nil {
		return nil, err
	}
	if err = form.Close(); err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, w.url+"/inference", &body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", form.FormDataContentType())
	resp, err := w.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return nil, fmt.Errorf("whisper.cpp: HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(msg)))
	}
	var result struct {
		Text             string `json:"text"`
		Language         string `json:"language"`
		DetectedLanguage string `json:"detected_language"`
	}
	if err = json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}
	detected := result.DetectedLanguage
	if detected == "" {
		detected = result.Language
	}
	return &transcript{text: result.Text, language: w.languageCode(detected)}, nil
}

// languageCode turns what Whisper reports ("Portuguese", "portuguese" or
// "pt") into the ISO 639-1 code Beeper stores with a transcript. A forced
// language wins; anything unrecognised becomes "auto", Beeper's own default.
func (w *whisper) languageCode(reported string) string {
	if w.language != "" {
		return w.language
	}
	reported = strings.ToLower(strings.TrimSpace(reported))
	if code, ok := whisperLanguages[reported]; ok {
		return code
	}
	for _, code := range whisperLanguages {
		if code == reported {
			return code
		}
	}
	return "auto"
}

// Whisper's language names (its tokenizer's LANGUAGES table), by code.
var whisperLanguages = map[string]string{
	"english": "en", "chinese": "zh", "german": "de", "spanish": "es", "russian": "ru", "korean": "ko",
	"french": "fr", "japanese": "ja", "portuguese": "pt", "turkish": "tr", "polish": "pl", "catalan": "ca",
	"dutch": "nl", "arabic": "ar", "swedish": "sv", "italian": "it", "indonesian": "id", "hindi": "hi",
	"finnish": "fi", "vietnamese": "vi", "hebrew": "he", "ukrainian": "uk", "greek": "el", "malay": "ms",
	"czech": "cs", "romanian": "ro", "danish": "da", "hungarian": "hu", "tamil": "ta", "norwegian": "no",
	"thai": "th", "urdu": "ur", "croatian": "hr", "bulgarian": "bg", "lithuanian": "lt", "latin": "la",
	"maori": "mi", "malayalam": "ml", "welsh": "cy", "slovak": "sk", "telugu": "te", "persian": "fa",
	"latvian": "lv", "bengali": "bn", "serbian": "sr", "azerbaijani": "az", "slovenian": "sl", "kannada": "kn",
	"estonian": "et", "macedonian": "mk", "breton": "br", "basque": "eu", "icelandic": "is", "armenian": "hy",
	"nepali": "ne", "mongolian": "mn", "bosnian": "bs", "kazakh": "kk", "albanian": "sq", "swahili": "sw",
	"galician": "gl", "marathi": "mr", "punjabi": "pa", "sinhala": "si", "khmer": "km", "shona": "sn",
	"yoruba": "yo", "somali": "so", "afrikaans": "af", "occitan": "oc", "georgian": "ka", "belarusian": "be",
	"tajik": "tg", "sindhi": "sd", "gujarati": "gu", "amharic": "am", "yiddish": "yi", "lao": "lo",
	"uzbek": "uz", "faroese": "fo", "haitian creole": "ht", "pashto": "ps", "turkmen": "tk", "nynorsk": "nn",
	"maltese": "mt", "sanskrit": "sa", "luxembourgish": "lb", "myanmar": "my", "tibetan": "bo", "tagalog": "tl",
	"malagasy": "mg", "assamese": "as", "tatar": "tt", "hawaiian": "haw", "lingala": "ln", "hausa": "ha",
	"bashkir": "ba", "javanese": "jw", "sundanese": "su", "cantonese": "yue",
}
