import math
import numpy as np
A1, A2, A3, A4 = 1.340264, -0.081106, 0.000893, 0.003796
M = math.sqrt(3) / 2
def raw(lon, lat):
    lam = np.radians(lon); phi = np.radians(lat)
    th = np.arcsin(M * np.sin(phi)); t2 = th * th; t6 = t2 ** 3
    x = lam * np.cos(th) / (M * (A1 + 3 * A2 * t2 + t6 * (7 * A3 + 9 * A4 * t2)))
    y = th * (A1 + A2 * t2 + t6 * (A3 + A4 * t2))
    return x, y
RX = raw(180.0, 0.0)[0]; RY = raw(0.0, 90.0)[1]; S = 1000 / (2 * RX)
def proj(lon, lat):
    x, y = raw(np.asarray(lon), np.asarray(lat)); return (x + RX) * S, (RY - y) * S

