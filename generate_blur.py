from pathlib import Path

from PIL import Image, ImageFilter

SRC = Path("ws-image-data")
DST = Path("ws-blur-image-data")


def main():
    if not SRC.exists():
        return

    for src_file in SRC.rglob("*.webp"):
        rel_path = src_file.relative_to(SRC)
        dst_file = DST / rel_path

        if dst_file.exists():
            continue

        try:
            dst_file.parent.mkdir(parents=True, exist_ok=True)

            with Image.open(src_file) as img:
                img.thumbnail((20, 20))
                img = img.filter(ImageFilter.GaussianBlur(radius=1))
                img.save(dst_file, "WEBP", quality=1, method=6)

            print(f"\rProcessed: {rel_path}\033[K", end="", flush=True)

        except Exception as e:
            print(f"\nError: {src_file} - {e}")

    print()


if __name__ == "__main__":
    main()
