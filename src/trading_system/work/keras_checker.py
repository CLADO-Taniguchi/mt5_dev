#!/usr/bin/env python3
"""
Keras依存関係チェックツール
プロジェクト内のKerasに依存したコードを検出します
"""

import os
import re
import glob
from pathlib import Path

def find_keras_imports(directory="."):
    """
    指定されたディレクトリ内のPythonファイルからKeras関連のimportを検出
    """
    keras_patterns = [
        r'^\s*import\s+keras\b',
        r'^\s*from\s+keras\b',
        r'^\s*import\s+.*keras.*',
        r'^\s*from\s+.*keras.*',
        r'\bkeras\.',
        r'keras\s*==',
        r'keras\s*>=',
        r'keras\s*<=',
        r'keras\s*!=',
        r'keras\s*~=',
    ]
    
    compiled_patterns = [re.compile(pattern, re.IGNORECASE | re.MULTILINE) for pattern in keras_patterns]
    
    results = []
    
    # Pythonファイルを検索
    for file_path in glob.glob(os.path.join(directory, "**/*.py"), recursive=True):
        try:
            with open(file_path, 'r', encoding='utf-8') as file:
                content = file.read()
                lines = content.split('\n')
                
                for line_num, line in enumerate(lines, 1):
                    for pattern in compiled_patterns:
                        if pattern.search(line):
                            results.append({
                                'file': file_path,
                                'line': line_num,
                                'content': line.strip(),
                                'type': 'keras_reference'
                            })
        except Exception as e:
            print(f"Warning: Could not read {file_path}: {e}")
    
    return results

def find_keras_in_requirements(directory="."):
    """
    requirements.txtファイル内のKeras依存関係を検出
    """
    requirements_files = [
        'requirements.txt',
        'requirements-dev.txt',
        'requirements-prod.txt',
        'pyproject.toml',
        'setup.py',
        'Pipfile'
    ]
    
    results = []
    
    for req_file in requirements_files:
        file_path = os.path.join(directory, req_file)
        if os.path.exists(file_path):
            try:
                with open(file_path, 'r', encoding='utf-8') as file:
                    lines = file.readlines()
                    
                for line_num, line in enumerate(lines, 1):
                    if re.search(r'\bkeras\b', line, re.IGNORECASE):
                        results.append({
                            'file': file_path,
                            'line': line_num,
                            'content': line.strip(),
                            'type': 'requirements'
                        })
            except Exception as e:
                print(f"Warning: Could not read {file_path}: {e}")
    
    return results

def analyze_tensorflow_keras_usage(directory="."):
    """
    TensorFlow.Kerasの使用パターンを分析
    """
    tf_keras_patterns = [
        r'tensorflow\.keras',
        r'tf\.keras',
        r'from\s+tensorflow\.keras',
        r'from\s+tf\.keras',
    ]
    
    compiled_patterns = [re.compile(pattern, re.IGNORECASE) for pattern in tf_keras_patterns]
    
    results = []
    
    for file_path in glob.glob(os.path.join(directory, "**/*.py"), recursive=True):
        try:
            with open(file_path, 'r', encoding='utf-8') as file:
                content = file.read()
                lines = content.split('\n')
                
                for line_num, line in enumerate(lines, 1):
                    for pattern in compiled_patterns:
                        if pattern.search(line):
                            results.append({
                                'file': file_path,
                                'line': line_num,
                                'content': line.strip(),
                                'type': 'tensorflow_keras'
                            })
        except Exception as e:
            print(f"Warning: Could not read {file_path}: {e}")
    
    return results

def generate_report(directory="."):
    """
    包括的なレポートを生成
    """
    print("=" * 60)
    print("Keras依存関係チェックレポート")
    print("=" * 60)
    print()
    
    # 1. 直接的なKeras import/usage
    print("1. 直接的なKeras参照:")
    print("-" * 30)
    keras_refs = find_keras_imports(directory)
    
    if keras_refs:
        for ref in keras_refs:
            print(f"📁 {ref['file']}:{ref['line']}")
            print(f"   {ref['content']}")
            print()
    else:
        print("✅ 直接的なKeras参照は見つかりませんでした")
        print()
    
    # 2. Requirements files
    print("2. 依存関係ファイル内のKeras:")
    print("-" * 30)
    req_refs = find_keras_in_requirements(directory)
    
    if req_refs:
        for ref in req_refs:
            print(f"📁 {ref['file']}:{ref['line']}")
            print(f"   {ref['content']}")
            print()
    else:
        print("✅ 依存関係ファイルにKerasは見つかりませんでした")
        print()
    
    # 3. TensorFlow.Keras usage
    print("3. TensorFlow.Kerasの使用:")
    print("-" * 30)
    tf_keras_refs = analyze_tensorflow_keras_usage(directory)
    
    if tf_keras_refs:
        for ref in tf_keras_refs:
            print(f"📁 {ref['file']}:{ref['line']}")
            print(f"   {ref['content']}")
            print()
    else:
        print("ℹ️  TensorFlow.Kerasの使用は見つかりませんでした")
        print()
    
    # 4. サマリー
    print("4. サマリー:")
    print("-" * 30)
    total_issues = len(keras_refs) + len(req_refs)
    
    if total_issues == 0:
        print("✅ 直接的なKeras依存関係は検出されませんでした")
        if tf_keras_refs:
            print("✅ TensorFlow.Kerasの使用が検出されました（推奨）")
    else:
        print(f"⚠️  {total_issues}個の潜在的なKeras依存関係が検出されました")
        print("   これらを修正することを推奨します")
    
    print()
    print("=" * 60)
    
    return {
        'keras_references': keras_refs,
        'requirements_references': req_refs,
        'tensorflow_keras_references': tf_keras_refs,
        'total_issues': total_issues
    }

def suggest_fixes(results):
    """
    修正提案を生成
    """
    if results['total_issues'] > 0:
        print("修正提案:")
        print("-" * 30)
        
        if results['keras_references']:
            print("📝 コード内のKeras参照を修正:")
            print("   import keras → from tensorflow import keras")
            print("   from keras import ... → from tensorflow.keras import ...")
            print()
        
        if results['requirements_references']:
            print("📝 requirements.txtからKerasを削除:")
            print("   keras==2.13.1 の行を削除または コメントアウト")
            print()
        
        print("📝 推奨されるimportパターン:")
        print("   from tensorflow import keras")
        print("   from tensorflow.keras.models import Sequential")
        print("   from tensorflow.keras.layers import Dense, LSTM")
        print()

if __name__ == "__main__":
    import sys
    
    # ディレクトリ指定（デフォルト: 現在のディレクトリ）
    target_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    
    if not os.path.exists(target_dir):
        print(f"Error: Directory '{target_dir}' does not exist")
        sys.exit(1)
    
    results = generate_report(target_dir)
    suggest_fixes(results)