// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package media

import (
	"image"
	"math"
	"strings"
)

const blurHashAlphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~"

// EncodeBlurHash computes a compact 4x3 BlurHash string from an image.Image
// after downsampling to at most 32x32 pixels in pure Go.
func EncodeBlurHash(img image.Image) string {
	if img == nil {
		return ""
	}
	b := img.Bounds()
	origW, origH := b.Dx(), b.Dy()
	if origW <= 0 || origH <= 0 {
		return ""
	}

	const (
		xComponents = 4
		yComponents = 3
		maxDim      = 32
	)
	w, h := min(origW, maxDim), min(origH, maxDim)

	pixels := make([][3]float64, w*h)
	for y := 0; y < h; y++ {
		srcY := b.Min.Y + (y*origH)/h
		for x := 0; x < w; x++ {
			srcX := b.Min.X + (x*origW)/w
			r16, g16, b16, a16 := img.At(srcX, srcY).RGBA()
			var r8, g8, b8 uint8
			if a16 == 0xffff {
				r8 = uint8(r16 >> 8)
				g8 = uint8(g16 >> 8)
				b8 = uint8(b16 >> 8)
			} else if a16 > 0 {
				r8 = uint8(min(255, (r16*0xff+a16/2)/a16))
				g8 = uint8(min(255, (g16*0xff+a16/2)/a16))
				b8 = uint8(min(255, (b16*0xff+a16/2)/a16))
			}
			pixels[y*w+x] = [3]float64{
				sRGBToLinear(r8),
				sRGBToLinear(g8),
				sRGBToLinear(b8),
			}
		}
	}

	factors := make([][3]float64, xComponents*yComponents)
	scale := 1.0 / float64(w*h)
	for j := 0; j < yComponents; j++ {
		for i := 0; i < xComponents; i++ {
			norm := 2.0
			if i == 0 && j == 0 {
				norm = 1.0
			}
			var rSum, gSum, bSum float64
			for y := 0; y < h; y++ {
				cosY := math.Cos(math.Pi * float64(j*y) / float64(h))
				for x := 0; x < w; x++ {
					basis := norm * math.Cos(math.Pi*float64(i*x)/float64(w)) * cosY
					p := pixels[y*w+x]
					rSum += basis * p[0]
					gSum += basis * p[1]
					bSum += basis * p[2]
				}
			}
			factors[j*xComponents+i] = [3]float64{
				rSum * scale,
				gSum * scale,
				bSum * scale,
			}
		}
	}

	var out strings.Builder
	out.Grow(28)

	sizeFlag := (xComponents - 1) + (yComponents-1)*9
	encodeBase83(&out, sizeFlag, 1)

	var maxAC float64
	for _, f := range factors[1:] {
		maxAC = max(maxAC, math.Abs(f[0]), math.Abs(f[1]), math.Abs(f[2]))
	}

	var quantisedMax int
	maximumValue := 1.0
	if maxAC > 0 {
		quantisedMax = max(0, min(82, int(math.Floor(maxAC*166.0-0.5))))
		maximumValue = float64(quantisedMax+1) / 166.0
	}
	encodeBase83(&out, quantisedMax, 1)

	dc := factors[0]
	dcVal := (linearToSRGB(dc[0]) << 16) + (linearToSRGB(dc[1]) << 8) + linearToSRGB(dc[2])
	encodeBase83(&out, dcVal, 4)

	for _, ac := range factors[1:] {
		qR := max(0, min(18, int(math.Floor(signPow(ac[0]/maximumValue, 0.5)*9.0+9.5))))
		qG := max(0, min(18, int(math.Floor(signPow(ac[1]/maximumValue, 0.5)*9.0+9.5))))
		qB := max(0, min(18, int(math.Floor(signPow(ac[2]/maximumValue, 0.5)*9.0+9.5))))
		encodeBase83(&out, qR*19*19+qG*19+qB, 2)
	}

	return out.String()
}

func sRGBToLinear(v uint8) float64 {
	x := float64(v) / 255.0
	if x <= 0.04045 {
		return x / 12.92
	}
	return math.Pow((x+0.055)/1.055, 2.4)
}

func linearToSRGB(x float64) int {
	v := max(0.0, min(1.0, x))
	if v <= 0.0031308 {
		return int(v*12.92*255.0 + 0.5)
	}
	return int((1.055*math.Pow(v, 1.0/2.4)-0.055)*255.0 + 0.5)
}

func signPow(val, exp float64) float64 {
	if val < 0 {
		return -math.Pow(-val, exp)
	}
	return math.Pow(val, exp)
}

func encodeBase83(out *strings.Builder, val, length int) {
	divisor := 1
	for i := 1; i < length; i++ {
		divisor *= 83
	}
	for i := 0; i < length; i++ {
		digit := (val / divisor) % 83
		out.WriteByte(blurHashAlphabet[digit])
		divisor /= 83
	}
}
