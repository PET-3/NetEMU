package com.netemu.netemu.vpn

import java.net.InetAddress

object PacketUtil {
    const val PROTO_ICMP = 1
    const val PROTO_TCP = 6
    const val PROTO_UDP = 17

    fun isIpv4(packet: ByteArray): Boolean =
        packet.size >= 20 && ((packet[0].toInt() ushr 4) and 0xF) == 4

    fun ihl(packet: ByteArray): Int = (packet[0].toInt() and 0x0F) * 4

    fun protocol(packet: ByteArray): Int = packet[9].toInt() and 0xFF

    fun srcAddr(packet: ByteArray): InetAddress =
        InetAddress.getByAddress(packet.copyOfRange(12, 16))

    fun dstAddr(packet: ByteArray): InetAddress =
        InetAddress.getByAddress(packet.copyOfRange(16, 20))

    fun srcPort(packet: ByteArray, ihl: Int): Int =
        ((packet[ihl].toInt() and 0xFF) shl 8) or (packet[ihl + 1].toInt() and 0xFF)

    fun dstPort(packet: ByteArray, ihl: Int): Int =
        ((packet[ihl + 2].toInt() and 0xFF) shl 8) or (packet[ihl + 3].toInt() and 0xFF)

    fun tcpFlags(packet: ByteArray, ihl: Int): Int =
        packet[ihl + 13].toInt() and 0xFF

    fun tcpHeaderLen(packet: ByteArray, ihl: Int): Int =
        ((packet[ihl + 12].toInt() and 0xF0) ushr 4) * 4

    fun udpPayload(packet: ByteArray, ihl: Int): ByteArray {
        if (packet.size <= ihl + 8) return ByteArray(0)
        return packet.copyOfRange(ihl + 8, packet.size)
    }

    fun tcpPayload(packet: ByteArray, ihl: Int): ByteArray {
        val thl = tcpHeaderLen(packet, ihl)
        val start = ihl + thl
        if (packet.size <= start) return ByteArray(0)
        return packet.copyOfRange(start, packet.size)
    }

    fun icmpType(packet: ByteArray, ihl: Int): Int =
        if (packet.size > ihl) packet[ihl].toInt() and 0xFF else -1

    fun icmpCode(packet: ByteArray, ihl: Int): Int =
        if (packet.size > ihl + 1) packet[ihl + 1].toInt() and 0xFF else -1

    fun checksum(data: ByteArray, offset: Int = 0, length: Int = data.size - offset): Int {
        var sum = 0L
        var i = offset
        val end = offset + length
        while (i + 1 < end) {
            sum += ((data[i].toInt() and 0xFF) shl 8) or (data[i + 1].toInt() and 0xFF)
            i += 2
        }
        if (i < end) sum += (data[i].toInt() and 0xFF) shl 8
        while (sum ushr 16 != 0L) sum = (sum and 0xFFFF) + (sum ushr 16)
        return (sum.inv() and 0xFFFF).toInt()
    }

    fun buildUdpPacket(
        src: InetAddress,
        dst: InetAddress,
        srcPort: Int,
        dstPort: Int,
        payload: ByteArray,
    ): ByteArray {
        val ihl = 20
        val udpLen = 8 + payload.size
        val total = ihl + udpLen
        val buf = ByteArray(total)
        buf[0] = 0x45.toByte()
        buf[2] = ((total ushr 8) and 0xFF).toByte()
        buf[3] = (total and 0xFF).toByte()
        buf[6] = 0x40.toByte()
        buf[8] = 64
        buf[9] = PROTO_UDP.toByte()
        System.arraycopy(src.address, 0, buf, 12, 4)
        System.arraycopy(dst.address, 0, buf, 16, 4)
        val ipCsum = checksum(buf, 0, 20)
        buf[10] = ((ipCsum ushr 8) and 0xFF).toByte()
        buf[11] = (ipCsum and 0xFF).toByte()
        buf[ihl] = ((srcPort ushr 8) and 0xFF).toByte()
        buf[ihl + 1] = (srcPort and 0xFF).toByte()
        buf[ihl + 2] = ((dstPort ushr 8) and 0xFF).toByte()
        buf[ihl + 3] = (dstPort and 0xFF).toByte()
        buf[ihl + 4] = ((udpLen ushr 8) and 0xFF).toByte()
        buf[ihl + 5] = (udpLen and 0xFF).toByte()
        System.arraycopy(payload, 0, buf, ihl + 8, payload.size)
        val pseudo = ByteArray(12 + udpLen)
        System.arraycopy(src.address, 0, pseudo, 0, 4)
        System.arraycopy(dst.address, 0, pseudo, 4, 4)
        pseudo[9] = PROTO_UDP.toByte()
        pseudo[10] = ((udpLen ushr 8) and 0xFF).toByte()
        pseudo[11] = (udpLen and 0xFF).toByte()
        System.arraycopy(buf, ihl, pseudo, 12, udpLen)
        val uCsum = checksum(pseudo)
        val finalCsum = if (uCsum == 0) 0xFFFF else uCsum
        buf[ihl + 6] = ((finalCsum ushr 8) and 0xFF).toByte()
        buf[ihl + 7] = (finalCsum and 0xFF).toByte()
        return buf
    }

    fun buildTcpPacket(
        src: InetAddress,
        dst: InetAddress,
        srcPort: Int,
        dstPort: Int,
        seq: Int,
        ack: Int,
        flags: Int,
        payload: ByteArray = ByteArray(0),
        window: Int = 65535,
    ): ByteArray {
        val ihl = 20
        val thl = 20
        val total = ihl + thl + payload.size
        val buf = ByteArray(total)
        buf[0] = 0x45.toByte()
        buf[2] = ((total ushr 8) and 0xFF).toByte()
        buf[3] = (total and 0xFF).toByte()
        buf[6] = 0x40.toByte()
        buf[8] = 64
        buf[9] = PROTO_TCP.toByte()
        System.arraycopy(src.address, 0, buf, 12, 4)
        System.arraycopy(dst.address, 0, buf, 16, 4)
        val ipCsum = checksum(buf, 0, 20)
        buf[10] = ((ipCsum ushr 8) and 0xFF).toByte()
        buf[11] = (ipCsum and 0xFF).toByte()
        val t = ihl
        buf[t] = ((srcPort ushr 8) and 0xFF).toByte()
        buf[t + 1] = (srcPort and 0xFF).toByte()
        buf[t + 2] = ((dstPort ushr 8) and 0xFF).toByte()
        buf[t + 3] = (dstPort and 0xFF).toByte()
        buf[t + 4] = ((seq ushr 24) and 0xFF).toByte()
        buf[t + 5] = ((seq ushr 16) and 0xFF).toByte()
        buf[t + 6] = ((seq ushr 8) and 0xFF).toByte()
        buf[t + 7] = (seq and 0xFF).toByte()
        buf[t + 8] = ((ack ushr 24) and 0xFF).toByte()
        buf[t + 9] = ((ack ushr 16) and 0xFF).toByte()
        buf[t + 10] = ((ack ushr 8) and 0xFF).toByte()
        buf[t + 11] = (ack and 0xFF).toByte()
        buf[t + 12] = 0x50.toByte()
        buf[t + 13] = (flags and 0xFF).toByte()
        buf[t + 14] = ((window ushr 8) and 0xFF).toByte()
        buf[t + 15] = (window and 0xFF).toByte()
        if (payload.isNotEmpty()) {
            System.arraycopy(payload, 0, buf, ihl + thl, payload.size)
        }
        val tcpLen = thl + payload.size
        val pseudo = ByteArray(12 + tcpLen)
        System.arraycopy(src.address, 0, pseudo, 0, 4)
        System.arraycopy(dst.address, 0, pseudo, 4, 4)
        pseudo[9] = PROTO_TCP.toByte()
        pseudo[10] = ((tcpLen ushr 8) and 0xFF).toByte()
        pseudo[11] = (tcpLen and 0xFF).toByte()
        System.arraycopy(buf, ihl, pseudo, 12, tcpLen)
        val tCsum = checksum(pseudo)
        buf[t + 16] = ((tCsum ushr 8) and 0xFF).toByte()
        buf[t + 17] = (tCsum and 0xFF).toByte()
        return buf
    }

    /**
     * Build ICMP Echo Reply from Echo Request.
     * Swaps src/dst, sets type=0, recomputes checksums.
     */
    fun buildIcmpEchoReply(request: ByteArray): ByteArray? {
        if (!isIpv4(request) || protocol(request) != PROTO_ICMP) return null
        val ihl = ihl(request)
        if (request.size < ihl + 8) return null
        if (icmpType(request, ihl) != 8) return null // only Echo Request

        val reply = request.copyOf()
        // Swap IP addresses
        System.arraycopy(request, 12, reply, 16, 4) // src -> dst
        System.arraycopy(request, 16, reply, 12, 4) // dst -> src
        reply[8] = 64 // TTL
        // Clear IP checksum then recompute
        reply[10] = 0
        reply[11] = 0
        val ipCsum = checksum(reply, 0, 20)
        reply[10] = ((ipCsum ushr 8) and 0xFF).toByte()
        reply[11] = (ipCsum and 0xFF).toByte()
        // ICMP type = 0 (Echo Reply)
        reply[ihl] = 0
        // Clear ICMP checksum and recompute over ICMP message
        reply[ihl + 2] = 0
        reply[ihl + 3] = 0
        val icmpLen = request.size - ihl
        val icmpCsum = checksum(reply, ihl, icmpLen)
        reply[ihl + 2] = ((icmpCsum ushr 8) and 0xFF).toByte()
        reply[ihl + 3] = (icmpCsum and 0xFF).toByte()
        return reply
    }

    fun readInt(packet: ByteArray, offset: Int): Int =
        ((packet[offset].toInt() and 0xFF) shl 24) or
            ((packet[offset + 1].toInt() and 0xFF) shl 16) or
            ((packet[offset + 2].toInt() and 0xFF) shl 8) or
            (packet[offset + 3].toInt() and 0xFF)
}
