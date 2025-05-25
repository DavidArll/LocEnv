# -*- mode: python ; coding: utf-8 -*-

a = Analysis(
    ['acquia_ddev_dashboard/main.py'],
    pathex=['.'],  # Add current directory to Python path
    binaries=[],
    datas=[
        ('acquia_ddev_dashboard/static', 'acquia_ddev_dashboard/static'),
        ('acquia_ddev_dashboard/templates', 'acquia_ddev_dashboard/templates')
    ],
    hiddenimports=['PyYAML', 'webview.platforms.qt', 'webview.platforms.gtk', 'webview.platforms.winforms'], # Added common pywebview backends
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='acquia_ddev_dashboard',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True, # Set to False for a GUI-only app on Windows, True for debugging
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='acquia_ddev_dashboard_dist', # Output directory name
)
