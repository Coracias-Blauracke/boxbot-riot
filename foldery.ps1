# Lista ścieżek do utworzenia (zgodna z naszym planem)
$folders = @(
    "autoloads",
    "core/enums",
    "core/models",
    "core/managers",
    "core/resource_scripts/effects",
    "content/items",
    "content/effects",
    "content/weapons",
    "scenes/actors/player/characters",
    "scenes/actors/enemies/variants",
    "scenes/levels",
    "scenes/ui",
    "scenes/weapons/ranged",
    "scenes/weapons/melee",
    "assets/sprites",
    "assets/sounds",
    "assets/fonts"
)

Write-Host "Budowanie struktury katalogów Godot 4..." -ForegroundColor Cyan

foreach ($folder in $folders) {
    # Tworzy folder i wszystkie brakujące foldery nadrzędne
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    Write-Host "Utworzono: $folder" -ForegroundColor Green
}

Write-Host "Gotowe! Możesz otworzyć projekt w Godocie." -ForegroundColor Yellow
Start-Sleep -Seconds 3