# Regras do R8 para o build de release.

# O plugin google_mlkit_text_recognition referencia os reconhecedores de todos
# os alfabetos que o ML Kit suporta — chinês, japonês, coreano e devanágari —
# mas só o latino é declarado como dependência. Etiqueta de encomenda no
# Brasil é alfabeto latino; puxar os outros aumentaria o APK em vários
# megabytes sem nenhum uso.
#
# Sem estas linhas o R8 falha o build inteiro ao não encontrar as classes.
# Elas nunca são chamadas em tempo de execução, porque o app pede
# explicitamente TextRecognitionScript.latin.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
