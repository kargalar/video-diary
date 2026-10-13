import os
import re
import sys


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def safe_print(*args, sep=' ', end='\n'):
    """Print text without crashing on non-UTF console encodings."""
    text = sep.join(str(arg) for arg in args) + end
    try:
        sys.stdout.write(text)
    except UnicodeEncodeError:
        encoding = sys.stdout.encoding or 'utf-8'
        safe_text = text.encode(encoding, errors='replace').decode(encoding, errors='replace')
        sys.stdout.write(safe_text)


def get_dart_files():
    dart_files = []
    lib_path = os.path.join(SCRIPT_DIR, 'lib')
    for root, _, files in os.walk(lib_path):
        for file in files:
            if file.endswith('.dart'):
                dart_files.append(os.path.join(root, file))
    return dart_files


def fix_with_opacity():
    """Replace withOpacity with withValues."""
    updated_count = 0

    for file_path in get_dart_files():
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()

            original_content = content
            content = re.sub(r'\.withOpacity\(([^)]+)\)', r'.withValues(alpha: \1)', content)

            if content != original_content:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(content)
                safe_print(f'✓ Updated: {file_path}')
                updated_count += 1
        except Exception as e:
            safe_print(f'✗ Error in {file_path}: {e}')

    safe_print(f'\nTotal files updated: {updated_count}')


def replace_print_with_debug_print():
    """Replace standalone print() calls with debugPrint()."""
    updated_count = 0

    for file_path in get_dart_files():
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()

            original_content = content
            content = re.sub(r'(?<![\w.])print\(', 'debugPrint(', content)

            if content != original_content:
                if "import 'package:flutter/foundation.dart';" not in content and content.startswith('import'):
                    imports_end = 0
                    for match in re.finditer(r'^import\s.*?;$', content, re.MULTILINE):
                        imports_end = match.end()
                    if imports_end > 0:
                        content = content[:imports_end] + "\nimport 'package:flutter/foundation.dart';" + content[imports_end:]

                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(content)
                safe_print(f'✓ Updated: {file_path}')
                updated_count += 1
        except Exception as e:
            safe_print(f'✗ Error in {file_path}: {e}')

    safe_print(f'\nTotal files updated: {updated_count}')


if __name__ == '__main__':
    safe_print('🔧 Starting Dart file fixes...\n')

    safe_print('=' * 50)
    safe_print('1. Fixing withOpacity -> withValues...')
    safe_print('=' * 50)
    fix_with_opacity()

    safe_print('\n' + '=' * 50)
    safe_print('2. Fixing print() -> debugPrint()...')
    safe_print('=' * 50)
    replace_print_with_debug_print()

    safe_print('\n✅ All fixes completed!')
