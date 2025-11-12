using System;

class Program
{
    //const int ITERS = 16;

    const int ITERS = 25;

    static void Main()
    {
        // Precompute the table of arctangents: thetaTable[i] = atan(1/2^i)
        double[] thetaTable = new double[ITERS];
        for ( int i = 0; i < ITERS; i++ )
        {
            thetaTable[i] = Math.Atan2(1, Math.Pow(2, i));
        }

        Console.WriteLine("  x       sin(x)     diff. sine     cos(x)    diff. cosine ");
        for ( int angleDeg = -90; angleDeg <= 90; angleDeg += 15 )
        {
            double rad = angleDeg * Math.PI / 180.0;
            // CORDIC returns (cosine, sine) approximations.
            (double cos_x, double sin_x) = CORDIC(rad, ITERS, thetaTable);

            // Calculate differences with the built-in Math.Sin and Math.Cos
            double diffSin = sin_x - Math.Sin(rad);
            double diffCos = cos_x - Math.Cos(rad);

            // Format the output using C# numeric format strings.
            Console.WriteLine(
                $"{angleDeg.ToString("+000.0;-000.0;+000.0")}°  " +
                $"{sin_x.ToString("+0.00000000;-0.00000000;+0.00000000")} " +
                $"({diffSin.ToString("+0.00000000;-0.00000000;+0.00000000")}) " +
                $"{cos_x.ToString("+0.00000000;-0.00000000;+0.00000000")} " +
                $"({diffCos.ToString("+0.00000000;-0.00000000;+0.00000000")})");
        }
    }

    /// <summary>
    /// Computes the scaling factor K(n) used in the CORDIC algorithm.
    /// </summary>
    static double ComputeK( int n )
    {
        double k = 1.0;
        for ( int i = 0; i < n; i++ )
        {
            k *= 1.0 / Math.Sqrt(1 + Math.Pow(2, -2 * i));
        }
        return k;
    }

    /// <summary>
    /// Performs the CORDIC rotation to approximate cosine and sine of the given angle (in radians).
    /// Returns a tuple (cos, sin).
    /// </summary>
    static (double, double) CORDIC( double alpha, int n, double[] thetaTable )
    {
        // Ensure that we do not exceed the precomputed table length.
        if ( n > ITERS )
        {
            throw new ArgumentException("n exceeds the precomputed table length.");
        }

        double K_n = ComputeK(n);
        double theta = 0.0;
        double x = 1.0;
        double y = 0.0;
        double P2i = 1.0; // Represents 2^(-i) at each iteration

        for ( int i = 0; i < n; i++ )
        {
            double arcTangent = thetaTable[i];
            // Determine the direction: sigma = +1 if theta is less than the target angle, -1 otherwise.
            int sigma = theta < alpha ? 1 : -1;
            theta += sigma * arcTangent;

            double newX = x - sigma * y * P2i;
            double newY = sigma * P2i * x + y;
            x = newX;
            y = newY;
            P2i /= 2;
        }
        return (x * K_n, y * K_n);
    }
}
