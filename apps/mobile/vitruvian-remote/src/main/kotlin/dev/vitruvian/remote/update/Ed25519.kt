// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package dev.vitruvian.remote.update

import java.math.BigInteger
import java.security.MessageDigest

/**
 * Ed25519 signature verification (RFC 8032, section 5.1.7), in plain Kotlin.
 *
 * Why not `java.security.Signature("Ed25519")`: Android only has it from API 33, and this app runs
 * from API 26. Why not a library: one verify of one small file per update check does not earn a new
 * dependency and its licence. This is the RFC's reference algorithm, checked against the RFC's own
 * test vectors and against the JDK's implementation in `Ed25519Test`.
 *
 * Verification only. Nothing here is secret, so it does not need to run in constant time.
 */
public object Ed25519 {
  // Not BigInteger.TWO: Android has it only from API 33.
  private val TWO: BigInteger = BigInteger.valueOf(2)
  private val P: BigInteger = TWO.pow(255).subtract(BigInteger.valueOf(19))
  private val Q: BigInteger = TWO.pow(252).add(BigInteger("27742317777372353535851937790883648493"))
  private val D: BigInteger =
      BigInteger.valueOf(-121665).multiply(inv(BigInteger.valueOf(121666))).mod(P)
  private val SQRT_M1: BigInteger = TWO.modPow(P.subtract(BigInteger.ONE).shiftRight(2), P)

  private class Point(val x: BigInteger, val y: BigInteger, val z: BigInteger, val t: BigInteger)

  private val G: Point = run {
    val y = BigInteger.valueOf(4).multiply(inv(BigInteger.valueOf(5))).mod(P)
    val x = recoverX(y, 0) ?: error("the base point does not decode")
    Point(x, y, BigInteger.ONE, x.multiply(y).mod(P))
  }

  /** True only when [signature] (64 bytes) is [publicKey]'s (32 bytes) signature of [message]. */
  public fun verify(message: ByteArray, signature: ByteArray, publicKey: ByteArray): Boolean {
    if (publicKey.size != 32 || signature.size != 64) return false
    val a = decompress(publicKey) ?: return false
    val rBytes = signature.copyOfRange(0, 32)
    val r = decompress(rBytes) ?: return false
    val s = littleEndian(signature.copyOfRange(32, 64))
    if (s >= Q) return false
    val digest = MessageDigest.getInstance("SHA-512")
    digest.update(rBytes)
    digest.update(publicKey)
    digest.update(message)
    val h = littleEndian(digest.digest()).mod(Q)
    return equal(multiply(s, G), add(r, multiply(h, a)))
  }

  private fun inv(x: BigInteger): BigInteger = x.modPow(P.subtract(TWO), P)

  private fun littleEndian(bytes: ByteArray): BigInteger = BigInteger(1, bytes.reversedArray())

  private fun add(p: Point, q: Point): Point {
    val a = p.y.subtract(p.x).multiply(q.y.subtract(q.x)).mod(P)
    val b = p.y.add(p.x).multiply(q.y.add(q.x)).mod(P)
    val c = p.t.multiply(TWO).multiply(D).multiply(q.t).mod(P)
    val d = p.z.multiply(TWO).multiply(q.z).mod(P)
    val e = b.subtract(a)
    val f = d.subtract(c)
    val g = d.add(c)
    val h = b.add(a)
    return Point(
        e.multiply(f).mod(P),
        g.multiply(h).mod(P),
        f.multiply(g).mod(P),
        e.multiply(h).mod(P),
    )
  }

  private fun multiply(scalar: BigInteger, point: Point): Point {
    var s = scalar
    var p = point
    var q = Point(BigInteger.ZERO, BigInteger.ONE, BigInteger.ONE, BigInteger.ZERO)
    while (s.signum() > 0) {
      if (s.testBit(0)) q = add(q, p)
      p = add(p, p)
      s = s.shiftRight(1)
    }
    return q
  }

  private fun equal(p: Point, q: Point): Boolean =
      p.x.multiply(q.z).subtract(q.x.multiply(p.z)).mod(P).signum() == 0 &&
          p.y.multiply(q.z).subtract(q.y.multiply(p.z)).mod(P).signum() == 0

  private fun recoverX(y: BigInteger, sign: Int): BigInteger? {
    if (y >= P) return null
    val y2 = y.multiply(y)
    val x2 = y2.subtract(BigInteger.ONE).multiply(inv(D.multiply(y2).add(BigInteger.ONE))).mod(P)
    if (x2.signum() == 0) return if (sign == 0) BigInteger.ZERO else null
    var x = x2.modPow(P.add(BigInteger.valueOf(3)).shiftRight(3), P)
    if (x.multiply(x).subtract(x2).mod(P).signum() != 0) x = x.multiply(SQRT_M1).mod(P)
    if (x.multiply(x).subtract(x2).mod(P).signum() != 0) return null
    if ((if (x.testBit(0)) 1 else 0) != sign) x = P.subtract(x)
    return x
  }

  private fun decompress(bytes: ByteArray): Point? {
    if (bytes.size != 32) return null
    val copy = bytes.copyOf()
    val sign = (copy[31].toInt() ushr 7) and 1
    copy[31] = (copy[31].toInt() and 0x7f).toByte()
    val y = littleEndian(copy)
    val x = recoverX(y, sign) ?: return null
    return Point(x, y, BigInteger.ONE, x.multiply(y).mod(P))
  }
}
