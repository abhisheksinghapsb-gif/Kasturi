import os
import struct
import zlib
import math
import random

def write_png(filepath, width, height, rgb_bytes):
    """Writes a 24-bit RGB PNG file using only Python standard library."""
    # PNG signature
    png_sig = b'\x89PNG\r\n\x1a\n'
    
    # IHDR chunk
    # width (4 bytes), height (4 bytes), bit depth (1 byte = 8), color type (1 byte = 2: RGB)
    # compression method (1 byte = 0), filter method (1 byte = 0), interlace method (1 byte = 0)
    ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    ihdr_crc = struct.pack('>I', zlib.crc32(b'IHDR' + ihdr_data) & 0xffffffff)
    ihdr_chunk = struct.pack('>I', len(ihdr_data)) + b'IHDR' + ihdr_data + ihdr_crc
    
    # IDAT chunk
    # Raw scanlines with filter byte 0x00 at the start of each row
    raw_scanlines = bytearray()
    row_bytes_len = width * 3
    for y in range(height):
        raw_scanlines.append(0) # Filter type 0 (None)
        start = y * row_bytes_len
        raw_scanlines.extend(rgb_bytes[start : start + row_bytes_len])
        
    compressed = zlib.compress(bytes(raw_scanlines), 9)
    idat_crc = struct.pack('>I', zlib.crc32(b'IDAT' + compressed) & 0xffffffff)
    idat_chunk = struct.pack('>I', len(compressed)) + b'IDAT' + compressed + idat_crc
    
    # IEND chunk
    iend_crc = struct.pack('>I', zlib.crc32(b'IEND') & 0xffffffff)
    iend_chunk = struct.pack('>I', 0) + b'IEND' + iend_crc
    
    with open(filepath, 'wb') as f:
        f.write(png_sig + ihdr_chunk + idat_chunk + iend_chunk)
        
    print(f"Generated PNG: {filepath} ({width}x{height}, {os.path.getsize(filepath)} bytes)")

def create_retina_image(width, height, grade=0, is_blur=False):
    cx = width / 2.0
    cy = height / 2.0
    fov_r = 0.46 * min(width, height)
    
    # Optic disc center (nasal)
    od_x = cx - 0.24 * width
    od_y = cy - 0.02 * height
    od_r = 0.075 * min(width, height)
    
    # Macula center (temporal)
    mac_x = cx + 0.16 * width
    mac_y = cy + 0.01 * height
    
    pixels = bytearray(width * height * 3)
    
    # Pre-calculate lesions for grade 2 and 4
    random.seed(42)
    mas = []
    if grade >= 2:
        num_ma = 30 if grade == 2 else 50
        for _ in range(num_ma):
            mx = mac_x + (random.random() - 0.5) * 0.45 * width
            my = cy + (random.random() - 0.5) * 0.45 * height
            mr = random.randint(2, 4)
            mas.append((mx, my, mr))
            
    exudates = []
    if grade >= 4:
        for _ in range(65):
            ang = random.random() * 2 * math.pi
            dist = (0.08 + 0.14 * random.random()) * min(width, height)
            ex = mac_x + dist * math.cos(ang)
            ey = mac_y + dist * math.sin(ang)
            er = random.randint(3, 7)
            exudates.append((ex, ey, er))
            
    # Glare coordinates for blur
    glare_x = 0.65 * width
    glare_y = 0.30 * height
    
    for y in range(height):
        for x in range(width):
            idx = (y * width + x) * 3
            dist_c = math.sqrt((x - cx)**2 + (y - cy)**2)
            
            if dist_c > fov_r:
                # Black background outside FOV
                pixels[idx] = 0
                pixels[idx+1] = 0
                pixels[idx+2] = 0
                continue
                
            edge_falloff = min(1.0, max(0.0, (fov_r - dist_c) / 8.0))
            
            # Base retina
            norm_d = dist_c / fov_r
            r = 0.82 - 0.12 * norm_d + 0.02 * math.sin(x / 20.0) * math.cos(y / 20.0)
            g = 0.42 - 0.10 * norm_d + 0.015 * math.cos(x / 25.0)
            b = 0.10 - 0.04 * norm_d
            
            # Optic disc
            dist_od = math.sqrt((x - od_x)**2 + (y - od_y)**2)
            if dist_od <= od_r * 1.1:
                od_w = math.exp(- (dist_od / (0.85 * od_r))**2)
                cup_w = math.exp(- (dist_od / (0.35 * od_r))**2) if dist_od <= 0.4 * od_r else 0.0
                r = r * (1.0 - 0.3 * od_w) + 0.98 * od_w + 0.15 * cup_w
                g = g * (1.0 - 0.6 * od_w) + 0.85 * od_w + 0.20 * cup_w
                b = b * (1.0 - 0.7 * od_w) + 0.45 * od_w + 0.15 * cup_w
                
            # Macula / Fovea
            dist_mac = math.sqrt((x - mac_x)**2 + (y - mac_y)**2)
            mac_w = math.exp(- (dist_mac / (0.12 * min(width, height)))**2)
            fov_w = math.exp(- (dist_mac / (0.03 * min(width, height)))**2)
            r = r * (1.0 - 0.22 * mac_w - 0.15 * fov_w)
            g = g * (1.0 - 0.30 * mac_w - 0.20 * fov_w)
            b = b * (1.0 - 0.20 * mac_w)
            
            # Primary Arching Vessel (approximation)
            # Superior arc
            dx_v1 = x - od_x
            dy_v1 = y - od_y
            arc1 = (dx_v1 / (0.35 * width))**2 + (dy_v1 / (0.38 * height) + 0.4)**2
            if 0.85 <= arc1 <= 1.05 and y < cy:
                v_w = 0.75
                r *= (1.0 - 0.25 * v_w)
                g *= (1.0 - 0.65 * v_w)
                b *= (1.0 - 0.40 * v_w)
                
            # Inferior arc
            arc2 = (dx_v1 / (0.35 * width))**2 + (dy_v1 / (0.38 * height) - 0.4)**2
            if 0.85 <= arc2 <= 1.05 and y > cy:
                v_w = 0.70
                r *= (1.0 - 0.25 * v_w)
                g *= (1.0 - 0.65 * v_w)
                b *= (1.0 - 0.40 * v_w)
                
            # Microaneurysms
            for mx, my, mr in mas:
                if (x - mx)**2 + (y - my)**2 <= mr**2:
                    r *= 0.45
                    g *= 0.15
                    b *= 0.10
                    
            # Hard Exudates (bright yellow)
            for ex, ey, er in exudates:
                if (x - ex)**2 + (y - ey)**2 <= er**2:
                    r = min(1.0, r * 0.3 + 0.95)
                    g = min(1.0, g * 0.3 + 0.92)
                    b = min(1.0, b * 0.3 + 0.50)
                    
            # Blur / Glare modification
            if is_blur:
                # Contrast wash out
                r = r * 0.45 + 0.15
                g = g * 0.45 + 0.15
                b = b * 0.45 + 0.15
                # Flash glare
                dist_glare = math.sqrt((x - glare_x)**2 + (y - glare_y)**2)
                glare = 0.75 * math.exp(- (dist_glare / (0.18 * width))**2)
                r = min(1.0, r + glare)
                g = min(1.0, g + glare)
                b = min(1.0, b + glare)
                
            r *= edge_falloff
            g *= edge_falloff
            b *= edge_falloff
            
            pixels[idx] = int(min(255, max(0, r * 255)))
            pixels[idx+1] = int(min(255, max(0, g * 255)))
            pixels[idx+2] = int(min(255, max(0, b * 255)))
            
    return pixels

def main():
    out_dir = "g:/sih/data/test_samples"
    os.makedirs(out_dir, exist_ok=True)
    
    W, H = 512, 512
    
    print("Generating prebuilt synthetic test samples...")
    # Grade 0
    p0 = create_retina_image(W, H, grade=0, is_blur=False)
    write_png(os.path.join(out_dir, "sample_grade0_healthy.png"), W, H, p0)
    
    # Grade 2
    p2 = create_retina_image(W, H, grade=2, is_blur=False)
    write_png(os.path.join(out_dir, "sample_grade2_moderate.png"), W, H, p2)
    
    # Grade 4
    p4 = create_retina_image(W, H, grade=4, is_blur=False)
    write_png(os.path.join(out_dir, "sample_grade4_severe.png"), W, H, p4)
    
    # Blur / Reject
    p_blur = create_retina_image(W, H, grade=0, is_blur=True)
    write_png(os.path.join(out_dir, "sample_blur_reject.png"), W, H, p_blur)
    
    print("Prebuilt samples generated successfully.")

if __name__ == "__main__":
    main()
