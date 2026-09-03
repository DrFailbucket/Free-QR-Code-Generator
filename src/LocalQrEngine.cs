using System;
using System.Collections.Generic;
using System.Text;

namespace LocalQr
{
    public sealed class QrResult
    {
        public bool[,] Modules;
        public int Version;
        public int Mask;
        public string ErrorCorrection;
    }

    internal sealed class RsBlock
    {
        public int TotalCount;
        public int DataCount;

        public RsBlock(int totalCount, int dataCount)
        {
            TotalCount = totalCount;
            DataCount = dataCount;
        }
    }

    internal sealed class BitBuffer
    {
        public readonly List<int> Buffer = new List<int>();
        public int Length;

        public void Put(int value, int length)
        {
            for (int i = 0; i < length; i++)
            {
                PutBit(((value >> (length - i - 1)) & 1) != 0);
            }
        }

        public void PutBit(bool bit)
        {
            int index = Length / 8;
            if (Buffer.Count <= index)
            {
                Buffer.Add(0);
            }

            if (bit)
            {
                Buffer[index] |= 0x80 >> (Length % 8);
            }

            Length++;
        }
    }

    public static class QrEncoder
    {
        private const int G15 = (1 << 10) | (1 << 8) | (1 << 5) | (1 << 4) | (1 << 2) | (1 << 1) | 1;
        private const int G18 = (1 << 12) | (1 << 11) | (1 << 10) | (1 << 9) | (1 << 8) | (1 << 5) | (1 << 2) | 1;
        private const int G15Mask = (1 << 14) | (1 << 12) | (1 << 10) | (1 << 4) | (1 << 1);

        private static readonly int[] ExpTable = new int[512];
        private static readonly int[] LogTable = new int[256];

        private static readonly int[][] RsBlockTable = new int[][]
        {
            new int[] { 1, 26, 19 },
            new int[] { 1, 26, 16 },
            new int[] { 1, 26, 13 },
            new int[] { 1, 26, 9 },
            new int[] { 1, 44, 34 },
            new int[] { 1, 44, 28 },
            new int[] { 1, 44, 22 },
            new int[] { 1, 44, 16 },
            new int[] { 1, 70, 55 },
            new int[] { 1, 70, 44 },
            new int[] { 2, 35, 17 },
            new int[] { 2, 35, 13 },
            new int[] { 1, 100, 80 },
            new int[] { 2, 50, 32 },
            new int[] { 2, 50, 24 },
            new int[] { 4, 25, 9 },
            new int[] { 1, 134, 108 },
            new int[] { 2, 67, 43 },
            new int[] { 2, 33, 15, 2, 34, 16 },
            new int[] { 2, 33, 11, 2, 34, 12 },
            new int[] { 2, 86, 68 },
            new int[] { 4, 43, 27 },
            new int[] { 4, 43, 19 },
            new int[] { 4, 43, 15 },
            new int[] { 2, 98, 78 },
            new int[] { 4, 49, 31 },
            new int[] { 2, 32, 14, 4, 33, 15 },
            new int[] { 4, 39, 13, 1, 40, 14 },
            new int[] { 2, 121, 97 },
            new int[] { 2, 60, 38, 2, 61, 39 },
            new int[] { 4, 40, 18, 2, 41, 19 },
            new int[] { 4, 40, 14, 2, 41, 15 },
            new int[] { 2, 146, 116 },
            new int[] { 3, 58, 36, 2, 59, 37 },
            new int[] { 4, 36, 16, 4, 37, 17 },
            new int[] { 4, 36, 12, 4, 37, 13 },
            new int[] { 2, 86, 68, 2, 87, 69 },
            new int[] { 4, 69, 43, 1, 70, 44 },
            new int[] { 6, 43, 19, 2, 44, 20 },
            new int[] { 6, 43, 15, 2, 44, 16 },
            new int[] { 4, 101, 81 },
            new int[] { 1, 80, 50, 4, 81, 51 },
            new int[] { 4, 50, 22, 4, 51, 23 },
            new int[] { 3, 36, 12, 8, 37, 13 },
            new int[] { 2, 116, 92, 2, 117, 93 },
            new int[] { 6, 58, 36, 2, 59, 37 },
            new int[] { 4, 46, 20, 6, 47, 21 },
            new int[] { 7, 42, 14, 4, 43, 15 },
            new int[] { 4, 133, 107 },
            new int[] { 8, 59, 37, 1, 60, 38 },
            new int[] { 8, 44, 20, 4, 45, 21 },
            new int[] { 12, 33, 11, 4, 34, 12 },
            new int[] { 3, 145, 115, 1, 146, 116 },
            new int[] { 4, 64, 40, 5, 65, 41 },
            new int[] { 11, 36, 16, 5, 37, 17 },
            new int[] { 11, 36, 12, 5, 37, 13 },
            new int[] { 5, 109, 87, 1, 110, 88 },
            new int[] { 5, 65, 41, 5, 66, 42 },
            new int[] { 5, 54, 24, 7, 55, 25 },
            new int[] { 11, 36, 12, 7, 37, 13 },
            new int[] { 5, 122, 98, 1, 123, 99 },
            new int[] { 7, 73, 45, 3, 74, 46 },
            new int[] { 15, 43, 19, 2, 44, 20 },
            new int[] { 3, 45, 15, 13, 46, 16 },
            new int[] { 1, 135, 107, 5, 136, 108 },
            new int[] { 10, 74, 46, 1, 75, 47 },
            new int[] { 1, 50, 22, 15, 51, 23 },
            new int[] { 2, 42, 14, 17, 43, 15 },
            new int[] { 5, 150, 120, 1, 151, 121 },
            new int[] { 9, 69, 43, 4, 70, 44 },
            new int[] { 17, 50, 22, 1, 51, 23 },
            new int[] { 2, 42, 14, 19, 43, 15 },
            new int[] { 3, 141, 113, 4, 142, 114 },
            new int[] { 3, 70, 44, 11, 71, 45 },
            new int[] { 17, 47, 21, 4, 48, 22 },
            new int[] { 9, 39, 13, 16, 40, 14 },
            new int[] { 3, 135, 107, 5, 136, 108 },
            new int[] { 3, 67, 41, 13, 68, 42 },
            new int[] { 15, 54, 24, 5, 55, 25 },
            new int[] { 15, 43, 15, 10, 44, 16 },
            new int[] { 4, 144, 116, 4, 145, 117 },
            new int[] { 17, 68, 42 },
            new int[] { 17, 50, 22, 6, 51, 23 },
            new int[] { 19, 46, 16, 6, 47, 17 },
            new int[] { 2, 139, 111, 7, 140, 112 },
            new int[] { 17, 74, 46 },
            new int[] { 7, 54, 24, 16, 55, 25 },
            new int[] { 34, 37, 13 },
            new int[] { 4, 151, 121, 5, 152, 122 },
            new int[] { 4, 75, 47, 14, 76, 48 },
            new int[] { 11, 54, 24, 14, 55, 25 },
            new int[] { 16, 45, 15, 14, 46, 16 },
            new int[] { 6, 147, 117, 4, 148, 118 },
            new int[] { 6, 73, 45, 14, 74, 46 },
            new int[] { 11, 54, 24, 16, 55, 25 },
            new int[] { 30, 46, 16, 2, 47, 17 },
            new int[] { 8, 132, 106, 4, 133, 107 },
            new int[] { 8, 75, 47, 13, 76, 48 },
            new int[] { 7, 54, 24, 22, 55, 25 },
            new int[] { 22, 45, 15, 13, 46, 16 },
            new int[] { 10, 142, 114, 2, 143, 115 },
            new int[] { 19, 74, 46, 4, 75, 47 },
            new int[] { 28, 50, 22, 6, 51, 23 },
            new int[] { 33, 46, 16, 4, 47, 17 },
            new int[] { 8, 152, 122, 4, 153, 123 },
            new int[] { 22, 73, 45, 3, 74, 46 },
            new int[] { 8, 53, 23, 26, 54, 24 },
            new int[] { 12, 45, 15, 28, 46, 16 },
            new int[] { 3, 147, 117, 10, 148, 118 },
            new int[] { 3, 73, 45, 23, 74, 46 },
            new int[] { 4, 54, 24, 31, 55, 25 },
            new int[] { 11, 45, 15, 31, 46, 16 },
            new int[] { 7, 146, 116, 7, 147, 117 },
            new int[] { 21, 73, 45, 7, 74, 46 },
            new int[] { 1, 53, 23, 37, 54, 24 },
            new int[] { 19, 45, 15, 26, 46, 16 },
            new int[] { 5, 145, 115, 10, 146, 116 },
            new int[] { 19, 75, 47, 10, 76, 48 },
            new int[] { 15, 54, 24, 25, 55, 25 },
            new int[] { 23, 45, 15, 25, 46, 16 },
            new int[] { 13, 145, 115, 3, 146, 116 },
            new int[] { 2, 74, 46, 29, 75, 47 },
            new int[] { 42, 54, 24, 1, 55, 25 },
            new int[] { 23, 45, 15, 28, 46, 16 },
            new int[] { 17, 145, 115 },
            new int[] { 10, 74, 46, 23, 75, 47 },
            new int[] { 10, 54, 24, 35, 55, 25 },
            new int[] { 19, 45, 15, 35, 46, 16 },
            new int[] { 17, 145, 115, 1, 146, 116 },
            new int[] { 14, 74, 46, 21, 75, 47 },
            new int[] { 29, 54, 24, 19, 55, 25 },
            new int[] { 11, 45, 15, 46, 46, 16 },
            new int[] { 13, 145, 115, 6, 146, 116 },
            new int[] { 14, 74, 46, 23, 75, 47 },
            new int[] { 44, 54, 24, 7, 55, 25 },
            new int[] { 59, 46, 16, 1, 47, 17 },
            new int[] { 12, 151, 121, 7, 152, 122 },
            new int[] { 12, 75, 47, 26, 76, 48 },
            new int[] { 39, 54, 24, 14, 55, 25 },
            new int[] { 22, 45, 15, 41, 46, 16 },
            new int[] { 6, 151, 121, 14, 152, 122 },
            new int[] { 6, 75, 47, 34, 76, 48 },
            new int[] { 46, 54, 24, 10, 55, 25 },
            new int[] { 2, 45, 15, 64, 46, 16 },
            new int[] { 17, 152, 122, 4, 153, 123 },
            new int[] { 29, 74, 46, 14, 75, 47 },
            new int[] { 49, 54, 24, 10, 55, 25 },
            new int[] { 24, 45, 15, 46, 46, 16 },
            new int[] { 4, 152, 122, 18, 153, 123 },
            new int[] { 13, 74, 46, 32, 75, 47 },
            new int[] { 48, 54, 24, 14, 55, 25 },
            new int[] { 42, 45, 15, 32, 46, 16 },
            new int[] { 20, 147, 117, 4, 148, 118 },
            new int[] { 40, 75, 47, 7, 76, 48 },
            new int[] { 43, 54, 24, 22, 55, 25 },
            new int[] { 10, 45, 15, 67, 46, 16 },
            new int[] { 19, 148, 118, 6, 149, 119 },
            new int[] { 18, 75, 47, 31, 76, 48 },
            new int[] { 34, 54, 24, 34, 55, 25 },
            new int[] { 20, 45, 15, 61, 46, 16 }
        };

        private static readonly int[][] PatternPositionTable = new int[][]
        {
            new int[0],
            new int[] { 6, 18 },
            new int[] { 6, 22 },
            new int[] { 6, 26 },
            new int[] { 6, 30 },
            new int[] { 6, 34 },
            new int[] { 6, 22, 38 },
            new int[] { 6, 24, 42 },
            new int[] { 6, 26, 46 },
            new int[] { 6, 28, 50 },
            new int[] { 6, 30, 54 },
            new int[] { 6, 32, 58 },
            new int[] { 6, 34, 62 },
            new int[] { 6, 26, 46, 66 },
            new int[] { 6, 26, 48, 70 },
            new int[] { 6, 26, 50, 74 },
            new int[] { 6, 30, 54, 78 },
            new int[] { 6, 30, 56, 82 },
            new int[] { 6, 30, 58, 86 },
            new int[] { 6, 34, 62, 90 },
            new int[] { 6, 28, 50, 72, 94 },
            new int[] { 6, 26, 50, 74, 98 },
            new int[] { 6, 30, 54, 78, 102 },
            new int[] { 6, 28, 54, 80, 106 },
            new int[] { 6, 32, 58, 84, 110 },
            new int[] { 6, 30, 58, 86, 114 },
            new int[] { 6, 34, 62, 90, 118 },
            new int[] { 6, 26, 50, 74, 98, 122 },
            new int[] { 6, 30, 54, 78, 102, 126 },
            new int[] { 6, 26, 52, 78, 104, 130 },
            new int[] { 6, 30, 56, 82, 108, 134 },
            new int[] { 6, 34, 60, 86, 112, 138 },
            new int[] { 6, 30, 58, 86, 114, 142 },
            new int[] { 6, 34, 62, 90, 118, 146 },
            new int[] { 6, 30, 54, 78, 102, 126, 150 },
            new int[] { 6, 24, 50, 76, 102, 128, 154 },
            new int[] { 6, 28, 54, 80, 106, 132, 158 },
            new int[] { 6, 32, 58, 84, 110, 136, 162 },
            new int[] { 6, 26, 54, 82, 110, 138, 166 },
            new int[] { 6, 30, 58, 86, 114, 142, 170 }
        };

        static QrEncoder()
        {
            for (int i = 0; i < 8; i++)
            {
                ExpTable[i] = 1 << i;
            }

            for (int i = 8; i < 256; i++)
            {
                ExpTable[i] = ExpTable[i - 4] ^ ExpTable[i - 5] ^ ExpTable[i - 6] ^ ExpTable[i - 8];
            }

            for (int i = 0; i < 255; i++)
            {
                LogTable[ExpTable[i]] = i;
            }

            for (int i = 256; i < ExpTable.Length; i++)
            {
                ExpTable[i] = ExpTable[i - 255];
            }
        }

        public static QrResult Encode(string data, string errorCorrection)
        {
            if (data == null)
            {
                data = String.Empty;
            }

            string ecc = NormalizeEcc(errorCorrection);
            byte[] bytes = new UTF8Encoding(false).GetBytes(data);
            bool useEci = ContainsNonAscii(data);
            int version = FindVersion(bytes.Length, ecc, useEci);
            int[] codewords = CreateCodewords(bytes, version, ecc, useEci);

            int bestMask = 0;
            int bestPenalty = Int32.MaxValue;

            for (int mask = 0; mask < 8; mask++)
            {
                bool[,] candidate = MakeMatrix(version, ecc, codewords, mask, true);
                int penalty = GetPenalty(candidate);
                if (penalty < bestPenalty)
                {
                    bestPenalty = penalty;
                    bestMask = mask;
                }
            }

            return new QrResult
            {
                Modules = MakeMatrix(version, ecc, codewords, bestMask, false),
                Version = version,
                Mask = bestMask,
                ErrorCorrection = ecc
            };
        }

        private static string NormalizeEcc(string ecc)
        {
            string normalized = String.IsNullOrWhiteSpace(ecc) ? "M" : ecc.Trim().ToUpperInvariant();
            if (normalized != "L" && normalized != "M" && normalized != "Q" && normalized != "H")
            {
                throw new ArgumentException("Unsupported QR error correction level: " + ecc);
            }
            return normalized;
        }

        private static bool ContainsNonAscii(string text)
        {
            for (int i = 0; i < text.Length; i++)
            {
                if (text[i] > 0x7F)
                {
                    return true;
                }
            }
            return false;
        }

        private static int FindVersion(int byteCount, string ecc, bool useEci)
        {
            for (int version = 1; version <= 40; version++)
            {
                int countBits = version < 10 ? 8 : 16;
                int requiredBits = (useEci ? 12 : 0) + 4 + countBits + (byteCount * 8);
                List<RsBlock> blocks = GetRsBlocks(version, ecc);
                int capacityBits = 0;

                for (int i = 0; i < blocks.Count; i++)
                {
                    capacityBits += blocks[i].DataCount * 8;
                }

                if (requiredBits <= capacityBits)
                {
                    return version;
                }
            }

            throw new InvalidOperationException("The QR payload is too large for QR Code version 40.");
        }

        private static List<RsBlock> GetRsBlocks(int version, string ecc)
        {
            int offset;
            switch (ecc)
            {
                case "L": offset = 0; break;
                case "M": offset = 1; break;
                case "Q": offset = 2; break;
                case "H": offset = 3; break;
                default: throw new ArgumentException("Invalid error correction level.");
            }

            int[] row = RsBlockTable[((version - 1) * 4) + offset];
            List<RsBlock> blocks = new List<RsBlock>();

            for (int i = 0; i < row.Length; i += 3)
            {
                int count = row[i];
                int totalCount = row[i + 1];
                int dataCount = row[i + 2];

                for (int j = 0; j < count; j++)
                {
                    blocks.Add(new RsBlock(totalCount, dataCount));
                }
            }

            return blocks;
        }

        private static int[] CreateCodewords(byte[] bytes, int version, string ecc, bool useEci)
        {
            BitBuffer buffer = new BitBuffer();

            if (useEci)
            {
                // ECI mode, assignment number 26 = UTF-8.
                buffer.Put(0x7, 4);
                buffer.Put(26, 8);
            }

            // Byte mode.
            buffer.Put(0x4, 4);
            buffer.Put(bytes.Length, version < 10 ? 8 : 16);

            for (int i = 0; i < bytes.Length; i++)
            {
                buffer.Put(bytes[i], 8);
            }

            List<RsBlock> blocks = GetRsBlocks(version, ecc);
            int bitLimit = 0;
            for (int i = 0; i < blocks.Count; i++)
            {
                bitLimit += blocks[i].DataCount * 8;
            }

            if (buffer.Length > bitLimit)
            {
                throw new InvalidOperationException("QR payload exceeds the selected QR version capacity.");
            }

            int terminator = Math.Min(4, bitLimit - buffer.Length);
            for (int i = 0; i < terminator; i++)
            {
                buffer.PutBit(false);
            }

            while ((buffer.Length % 8) != 0)
            {
                buffer.PutBit(false);
            }

            int padIndex = 0;
            while (buffer.Length < bitLimit)
            {
                buffer.Put((padIndex % 2) == 0 ? 0xEC : 0x11, 8);
                padIndex++;
            }

            List<int[]> dataBlocks = new List<int[]>();
            List<int[]> eccBlocks = new List<int[]>();
            int offset = 0;
            int maxDataCount = 0;
            int maxEccCount = 0;

            for (int i = 0; i < blocks.Count; i++)
            {
                RsBlock block = blocks[i];
                int[] dataBlock = new int[block.DataCount];

                for (int j = 0; j < block.DataCount; j++)
                {
                    dataBlock[j] = buffer.Buffer[offset + j] & 0xFF;
                }

                offset += block.DataCount;
                int eccCount = block.TotalCount - block.DataCount;
                int[] eccBlock = CalculateErrorCorrection(dataBlock, eccCount);

                dataBlocks.Add(dataBlock);
                eccBlocks.Add(eccBlock);
                maxDataCount = Math.Max(maxDataCount, dataBlock.Length);
                maxEccCount = Math.Max(maxEccCount, eccBlock.Length);
            }

            List<int> output = new List<int>();

            for (int i = 0; i < maxDataCount; i++)
            {
                for (int j = 0; j < dataBlocks.Count; j++)
                {
                    if (i < dataBlocks[j].Length)
                    {
                        output.Add(dataBlocks[j][i]);
                    }
                }
            }

            for (int i = 0; i < maxEccCount; i++)
            {
                for (int j = 0; j < eccBlocks.Count; j++)
                {
                    if (i < eccBlocks[j].Length)
                    {
                        output.Add(eccBlocks[j][i]);
                    }
                }
            }

            return output.ToArray();
        }

        private static int[] CalculateErrorCorrection(int[] data, int eccCount)
        {
            int[] generator = BuildGenerator(eccCount);
            int[] message = new int[data.Length + eccCount];

            for (int i = 0; i < data.Length; i++)
            {
                message[i] = data[i];
            }

            for (int i = 0; i < data.Length; i++)
            {
                int factor = message[i];
                if (factor == 0)
                {
                    continue;
                }

                int factorLog = GLog(factor);
                for (int j = 0; j < generator.Length; j++)
                {
                    int coefficient = generator[j];
                    if (coefficient != 0)
                    {
                        message[i + j] ^= GExp(factorLog + GLog(coefficient));
                    }
                }
            }

            int[] result = new int[eccCount];
            Array.Copy(message, data.Length, result, 0, eccCount);
            return result;
        }

        private static int[] BuildGenerator(int degree)
        {
            int[] result = new int[] { 1 };

            for (int i = 0; i < degree; i++)
            {
                result = MultiplyPolynomials(result, new int[] { 1, GExp(i) });
            }

            return result;
        }

        private static int[] MultiplyPolynomials(int[] left, int[] right)
        {
            int[] result = new int[left.Length + right.Length - 1];

            for (int i = 0; i < left.Length; i++)
            {
                if (left[i] == 0)
                {
                    continue;
                }

                int leftLog = GLog(left[i]);
                for (int j = 0; j < right.Length; j++)
                {
                    if (right[j] != 0)
                    {
                        result[i + j] ^= GExp(leftLog + GLog(right[j]));
                    }
                }
            }

            return result;
        }

        private static int GLog(int value)
        {
            if (value < 1)
            {
                throw new ArgumentOutOfRangeException("value");
            }
            return LogTable[value];
        }

        private static int GExp(int value)
        {
            int normalized = value % 255;
            if (normalized < 0)
            {
                normalized += 255;
            }
            return ExpTable[normalized];
        }

        private static bool[,] MakeMatrix(int version, string ecc, int[] data, int mask, bool test)
        {
            int size = (version * 4) + 17;
            bool?[,] modules = new bool?[size, size];

            SetupFinder(modules, 0, 0);
            SetupFinder(modules, size - 7, 0);
            SetupFinder(modules, 0, size - 7);
            SetupAlignment(modules, version);
            SetupTiming(modules);
            SetupFormatInfo(modules, ecc, mask, test);

            if (version >= 7)
            {
                SetupVersionInfo(modules, version, test);
            }

            MapData(modules, data, mask);

            bool[,] result = new bool[size, size];
            for (int row = 0; row < size; row++)
            {
                for (int col = 0; col < size; col++)
                {
                    result[row, col] = modules[row, col].HasValue && modules[row, col].Value;
                }
            }
            return result;
        }

        private static void SetupFinder(bool?[,] modules, int row, int col)
        {
            int size = modules.GetLength(0);

            for (int r = -1; r <= 7; r++)
            {
                int targetRow = row + r;
                if (targetRow < 0 || targetRow >= size)
                {
                    continue;
                }

                for (int c = -1; c <= 7; c++)
                {
                    int targetCol = col + c;
                    if (targetCol < 0 || targetCol >= size)
                    {
                        continue;
                    }

                    bool dark =
                        (r >= 0 && r <= 6 && (c == 0 || c == 6)) ||
                        (c >= 0 && c <= 6 && (r == 0 || r == 6)) ||
                        (r >= 2 && r <= 4 && c >= 2 && c <= 4);

                    modules[targetRow, targetCol] = dark;
                }
            }
        }

        private static void SetupTiming(bool?[,] modules)
        {
            int size = modules.GetLength(0);

            for (int row = 8; row < size - 8; row++)
            {
                if (!modules[row, 6].HasValue)
                {
                    modules[row, 6] = (row % 2) == 0;
                }
            }

            for (int col = 8; col < size - 8; col++)
            {
                if (!modules[6, col].HasValue)
                {
                    modules[6, col] = (col % 2) == 0;
                }
            }
        }

        private static void SetupAlignment(bool?[,] modules, int version)
        {
            int[] positions = PatternPositionTable[version - 1];

            for (int i = 0; i < positions.Length; i++)
            {
                int row = positions[i];

                for (int j = 0; j < positions.Length; j++)
                {
                    int col = positions[j];
                    if (modules[row, col].HasValue)
                    {
                        continue;
                    }

                    for (int r = -2; r <= 2; r++)
                    {
                        for (int c = -2; c <= 2; c++)
                        {
                            modules[row + r, col + c] =
                                r == -2 || r == 2 || c == -2 || c == 2 || (r == 0 && c == 0);
                        }
                    }
                }
            }
        }

        private static void SetupVersionInfo(bool?[,] modules, int version, bool test)
        {
            int size = modules.GetLength(0);
            int bits = BchTypeNumber(version);

            for (int i = 0; i < 18; i++)
            {
                bool dark = !test && (((bits >> i) & 1) != 0);
                modules[i / 3, (i % 3) + size - 11] = dark;
                modules[(i % 3) + size - 11, i / 3] = dark;
            }
        }

        private static void SetupFormatInfo(bool?[,] modules, string ecc, int mask, bool test)
        {
            int size = modules.GetLength(0);
            int eccBits;

            switch (ecc)
            {
                case "L": eccBits = 1; break;
                case "M": eccBits = 0; break;
                case "Q": eccBits = 3; break;
                case "H": eccBits = 2; break;
                default: throw new ArgumentException("Invalid error correction level.");
            }

            int bits = BchTypeInfo((eccBits << 3) | mask);

            for (int i = 0; i < 15; i++)
            {
                bool dark = !test && (((bits >> i) & 1) != 0);

                if (i < 6)
                {
                    modules[i, 8] = dark;
                }
                else if (i < 8)
                {
                    modules[i + 1, 8] = dark;
                }
                else
                {
                    modules[size - 15 + i, 8] = dark;
                }
            }

            for (int i = 0; i < 15; i++)
            {
                bool dark = !test && (((bits >> i) & 1) != 0);

                if (i < 8)
                {
                    modules[8, size - i - 1] = dark;
                }
                else if (i < 9)
                {
                    modules[8, 15 - i] = dark;
                }
                else
                {
                    modules[8, 15 - i - 1] = dark;
                }
            }

            modules[size - 8, 8] = !test;
        }

        private static void MapData(bool?[,] modules, int[] data, int mask)
        {
            int size = modules.GetLength(0);
            int increment = -1;
            int row = size - 1;
            int bitIndex = 7;
            int byteIndex = 0;

            for (int rawCol = size - 1; rawCol > 0; rawCol -= 2)
            {
                int col = rawCol;
                if (col <= 6)
                {
                    col--;
                }

                while (true)
                {
                    for (int offset = 0; offset < 2; offset++)
                    {
                        int currentCol = col - offset;

                        if (!modules[row, currentCol].HasValue)
                        {
                            bool dark = false;

                            if (byteIndex < data.Length)
                            {
                                dark = (((data[byteIndex] >> bitIndex) & 1) != 0);
                            }

                            if (Mask(mask, row, currentCol))
                            {
                                dark = !dark;
                            }

                            modules[row, currentCol] = dark;
                            bitIndex--;

                            if (bitIndex < 0)
                            {
                                byteIndex++;
                                bitIndex = 7;
                            }
                        }
                    }

                    row += increment;
                    if (row < 0 || row >= size)
                    {
                        row -= increment;
                        increment = -increment;
                        break;
                    }
                }
            }
        }

        private static bool Mask(int pattern, int row, int col)
        {
            switch (pattern)
            {
                case 0: return ((row + col) % 2) == 0;
                case 1: return (row % 2) == 0;
                case 2: return (col % 3) == 0;
                case 3: return ((row + col) % 3) == 0;
                case 4: return (((row / 2) + (col / 3)) % 2) == 0;
                case 5: return ((row * col) % 2) + ((row * col) % 3) == 0;
                case 6: return ((((row * col) % 2) + ((row * col) % 3)) % 2) == 0;
                case 7: return ((((row * col) % 3) + ((row + col) % 2)) % 2) == 0;
                default: throw new ArgumentOutOfRangeException("pattern");
            }
        }

        private static int GetPenalty(bool[,] modules)
        {
            int size = modules.GetLength(0);
            int penalty = 0;

            for (int row = 0; row < size; row++)
            {
                int run = 1;
                for (int col = 1; col < size; col++)
                {
                    if (modules[row, col] == modules[row, col - 1])
                    {
                        run++;
                    }
                    else
                    {
                        if (run >= 5)
                        {
                            penalty += run - 2;
                        }
                        run = 1;
                    }
                }
                if (run >= 5)
                {
                    penalty += run - 2;
                }
            }

            for (int col = 0; col < size; col++)
            {
                int run = 1;
                for (int row = 1; row < size; row++)
                {
                    if (modules[row, col] == modules[row - 1, col])
                    {
                        run++;
                    }
                    else
                    {
                        if (run >= 5)
                        {
                            penalty += run - 2;
                        }
                        run = 1;
                    }
                }
                if (run >= 5)
                {
                    penalty += run - 2;
                }
            }

            for (int row = 0; row < size - 1; row++)
            {
                for (int col = 0; col < size - 1; col++)
                {
                    bool value = modules[row, col];
                    if (modules[row + 1, col] == value &&
                        modules[row, col + 1] == value &&
                        modules[row + 1, col + 1] == value)
                    {
                        penalty += 3;
                    }
                }
            }

            int[] pattern1 = new int[] { 1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0 };
            int[] pattern2 = new int[] { 0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1 };

            for (int row = 0; row < size; row++)
            {
                for (int col = 0; col <= size - 11; col++)
                {
                    if (MatchesRow(modules, row, col, pattern1) || MatchesRow(modules, row, col, pattern2))
                    {
                        penalty += 40;
                    }
                }
            }

            for (int col = 0; col < size; col++)
            {
                for (int row = 0; row <= size - 11; row++)
                {
                    if (MatchesColumn(modules, row, col, pattern1) || MatchesColumn(modules, row, col, pattern2))
                    {
                        penalty += 40;
                    }
                }
            }

            int darkCount = 0;
            for (int row = 0; row < size; row++)
            {
                for (int col = 0; col < size; col++)
                {
                    if (modules[row, col])
                    {
                        darkCount++;
                    }
                }
            }

            double percent = (darkCount * 100.0) / (size * size);
            penalty += ((int)(Math.Abs(percent - 50.0) / 5.0)) * 10;
            return penalty;
        }

        private static bool MatchesRow(bool[,] modules, int row, int startCol, int[] pattern)
        {
            for (int i = 0; i < pattern.Length; i++)
            {
                if (modules[row, startCol + i] != (pattern[i] == 1))
                {
                    return false;
                }
            }
            return true;
        }

        private static bool MatchesColumn(bool[,] modules, int startRow, int col, int[] pattern)
        {
            for (int i = 0; i < pattern.Length; i++)
            {
                if (modules[startRow + i, col] != (pattern[i] == 1))
                {
                    return false;
                }
            }
            return true;
        }

        private static int BchTypeInfo(int data)
        {
            int value = data << 10;
            while (BchDigit(value) - BchDigit(G15) >= 0)
            {
                value ^= G15 << (BchDigit(value) - BchDigit(G15));
            }
            return ((data << 10) | value) ^ G15Mask;
        }

        private static int BchTypeNumber(int data)
        {
            int value = data << 12;
            while (BchDigit(value) - BchDigit(G18) >= 0)
            {
                value ^= G18 << (BchDigit(value) - BchDigit(G18));
            }
            return (data << 12) | value;
        }

        private static int BchDigit(int value)
        {
            int digit = 0;
            while (value != 0)
            {
                digit++;
                value >>= 1;
            }
            return digit;
        }
    }
}
