Add-Type @"
using System;
using System.Net;
using System.Net.Sockets;
using System.IO;
using System.Threading;
using System.Globalization;

public class MultiplayerSync {
    public static void Start(string ip, string currentPath) {
        Console.WriteLine("=========================================");
        Console.WriteLine("  LAST CARETAKER - MULTIPLAYER NETWORK");
        Console.WriteLine("  Sending coordinates to: " + ip);
        Console.WriteLine("  Listening on port: 27015");
        Console.WriteLine("  Press CTRL+C to stop");
        Console.WriteLine("=========================================");

        string fileOut = Path.Combine(currentPath, "coords_out.txt");
        string fileIn = Path.Combine(currentPath, "coords_in.txt");

        // 1. Receive Thread (From friend to you)
        Thread receiverThread = new Thread(() => {
            UdpClient listener = new UdpClient(27015);
            IPEndPoint groupEP = new IPEndPoint(IPAddress.Any, 27015);
            bool connected = false;

            try {
                while (true) {
                    byte[] bytes = listener.Receive(ref groupEP);
                    if (bytes.Length > 0) {
                        if (!connected) {
                            connected = true;
                            Console.ForegroundColor = ConsoleColor.Green;
                            Console.WriteLine("[NETWORK] Player connected!");
                            Console.ResetColor();
                        }

                        byte packetType = bytes[0];

                        if (packetType == 1 && bytes.Length >= 13) {
                            // Coordinates
                            float x = BitConverter.ToSingle(bytes, 1);
                            float y = BitConverter.ToSingle(bytes, 5);
                            float z = BitConverter.ToSingle(bytes, 9);
                            float yaw = (bytes.Length >= 17) ? BitConverter.ToSingle(bytes, 13) : 0.0f;
                            
                            try {
                                using (FileStream fs = new FileStream(fileIn, FileMode.Create, FileAccess.Write, FileShare.ReadWrite))
                                using (StreamWriter sw = new StreamWriter(fs)) {
                                    sw.Write(x.ToString(CultureInfo.InvariantCulture) + "," + 
                                             y.ToString(CultureInfo.InvariantCulture) + "," + 
                                             z.ToString(CultureInfo.InvariantCulture) + "," + 
                                             yaw.ToString(CultureInfo.InvariantCulture) + ",1");
                                }
                            } catch (IOException) { }
                        }
                        else if (packetType == 2 && bytes.Length > 1) {
                            // Events (e.g. Doors)
                            string eventData = System.Text.Encoding.UTF8.GetString(bytes, 1, bytes.Length - 1);
                            Console.ForegroundColor = ConsoleColor.Yellow;
                            Console.WriteLine("[NETWORK EVENT] Received: " + eventData);
                            Console.ResetColor();

                            try {
                                string eventFileIn = Path.Combine(currentPath, "event_in.txt");
                                using (FileStream fs = new FileStream(eventFileIn, FileMode.Append, FileAccess.Write, FileShare.ReadWrite))
                                using (StreamWriter sw = new StreamWriter(fs)) {
                                    sw.WriteLine(eventData);
                                }
                            } catch (IOException) { }
                        }
                    }
                }
            } catch (Exception) {
                listener.Close();
            }
        });
        receiverThread.IsBackground = true;
        receiverThread.Start();

        // 2. Send Thread (From you to friend)
        UdpClient sender = new UdpClient();
        IPEndPoint targetEP = new IPEndPoint(IPAddress.Parse(ip.Trim()), 27015);
        float lastX = 0, lastY = 0, lastZ = 0, lastYaw = 0;
        int frames = 0;

        while (true) {
            try {
                if (File.Exists(fileOut)) {
                    using (FileStream fs = new FileStream(fileOut, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                    using (StreamReader sr = new StreamReader(fs)) {
                        string line = sr.ReadLine();
                        if (!string.IsNullOrEmpty(line)) {
                            string[] parts = line.Split(',');
                            if (parts.Length >= 3) {
                                float x = float.Parse(parts[0], CultureInfo.InvariantCulture);
                                float y = float.Parse(parts[1], CultureInfo.InvariantCulture);
                                float z = float.Parse(parts[2], CultureInfo.InvariantCulture);
                                float yaw = 0;
                                float parsedYaw;
                                if (parts.Length > 3 && float.TryParse(parts[3], NumberStyles.Any, CultureInfo.InvariantCulture, out parsedYaw)) {
                                    yaw = parsedYaw;
                                }

                                byte[] packet = new byte[17];
                                packet[0] = 1; 
                                BitConverter.GetBytes(x).CopyTo(packet, 1);
                                BitConverter.GetBytes(y).CopyTo(packet, 5);
                                BitConverter.GetBytes(z).CopyTo(packet, 9);
                                BitConverter.GetBytes(yaw).CopyTo(packet, 13);

                                sender.Send(packet, packet.Length, targetEP);
                                
                                if (x != lastX || y != lastY || z != lastZ || yaw != lastYaw) {
                                    lastX = x; lastY = y; lastZ = z; lastYaw = yaw;
                                    Console.WriteLine("[SEND] X:" + x.ToString("F1") + " Y:" + y.ToString("F1") + " Z:" + z.ToString("F1") + " Yaw:" + yaw.ToString("F1"));
                                    frames = 0;
                                } else {
                                    frames++;
                                    if (frames > 30) {
                                        Console.WriteLine("[SEND] (Idle) Maintaining connection... X:" + x.ToString("F1"));
                                        frames = 0;
                                    }
                                }
                            }
                        }
                    }
                }
                
                // --- EVENTS SENDING ---
                string eventFileOut = Path.Combine(currentPath, "event_out.txt");
                if (File.Exists(eventFileOut)) {
                    string[] events;
                    try {
                        using (FileStream fs = new FileStream(eventFileOut, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                        using (StreamReader sr = new StreamReader(fs)) {
                            string content = sr.ReadToEnd();
                            events = content.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                        }
                        
                        // Clear the file after reading
                        using (FileStream fs = new FileStream(eventFileOut, FileMode.Truncate, FileAccess.Write, FileShare.ReadWrite)) { }
                        
                        foreach (string ev in events) {
                            if (!string.IsNullOrEmpty(ev)) {
                                byte[] strBytes = System.Text.Encoding.UTF8.GetBytes(ev);
                                byte[] packet = new byte[strBytes.Length + 1];
                                packet[0] = 2; // Magic byte for Events
                                strBytes.CopyTo(packet, 1);
                                sender.Send(packet, packet.Length, targetEP);
                                Console.ForegroundColor = ConsoleColor.Cyan;
                                Console.WriteLine("[NETWORK EVENT] Sent: " + ev);
                                Console.ResetColor();
                            }
                        }
                    } catch (IOException) { }
                }
                // --- END EVENTS SENDING ---
                
            } catch (Exception ex) {
                Console.WriteLine("[DEBUG] ERROR: " + ex.Message);
            }

            Thread.Sleep(33); // Loop at ~30 FPS
        }
    }
}
"@

$ip = Read-Host "Enter the other player's IP address (e.g., 192.168.1.55 or 127.0.0.1)"
$currentPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
[MultiplayerSync]::Start($ip, $currentPath)
