
/*
 * Note: The following tests do not have 80 bits floating point precision as in the 8087 FPU
 * they are mere evaluations of the algorithms and may not be accurate to the last bit.
 */

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace CordicTest
{
    using System;

    public class CordicCalculator
    {

        // precomputed angles
        private static double[] angles;


        private static double[] scaleFactors;


        const int SQRTITERATIONS = 64;
        static readonly double[] arctanTable = new double[SQRTITERATIONS];
        static readonly double[] pow2Table = new double[SQRTITERATIONS];
        static readonly double[] K_VALUES = new double[SQRTITERATIONS];

        static CordicCalculator()
        {

            angles = new double[25];
            for (int i = 0; i < 25; i++)
            {
                angles[i] = Math.Atan(Math.Pow(2, -i));
            }

            // Initialize K_VALUES for each iteration
            for (int i = 0; i < SQRTITERATIONS; i++)
            {
                K_VALUES[i] = 1 / Math.Sqrt(1 + Math.Pow(2, -2 * i));
            }


            scaleFactors = new double[angles.Length];
            double cumulativeScaleFactor = 1.0; // This will hold the product of all scale factors
            for (int i = 0; i < angles.Length; i++)
            {
                double individualScaleFactor = Math.Sqrt(1 + Math.Pow(2, -2 * i));
                cumulativeScaleFactor *= individualScaleFactor;
                scaleFactors[i] = cumulativeScaleFactor; // This line is only needed if you use individual scale factors
            }


            // Precalculate arctan and pow2i values
            for (int i = 0; i < SQRTITERATIONS; i++)
            {
                arctanTable[i] = Math.Atan(Math.Pow(2, -i));
                pow2Table[i] = Math.Pow(2, -i);
            }
        }


        public static double CordicSqrtn2(double value)
        {
            // Initial values for CORDIC in vectoring mode for square root
            double x = value / 2.0 + 1.0;
            double y = value / 2.0 - 1.0;
            double target = 0.0;

            // Iterative CORDIC algorithm
            for (int i = 0; i < SQRTITERATIONS; i++)
            {
                double shift = Math.Pow(2, -i);
                double newX, newY;

                if (y < 0)
                {
                    newX = x - shift * y;
                    newY = y + shift * x;
                    target -= shift;
                }
                else
                {
                    newX = x + shift * y;
                    newY = y - shift * x;
                    target += shift;
                }

                x = newX;
                y = newY;
            }

            // The square root is approximately the x value adjusted by the target
            return x - target;
        }

        public static double CordicSqrtn0(double S)
        {
            double x = S + 1.0;
            double y = S - 1.0;

            for (int i = 0; i < SQRTITERATIONS; i++)
            {
                double di = y >= 0 ? -1 : 1;

                // Use precalculated pow2i values
                double xNew = x - di * y * pow2Table[i];
                double yNew = y + di * x * pow2Table[i];

                x = xNew;
                y = yNew;
            }

            return x;
        }

        public static double SqrtGoldschmidt(double number)
        {
            if (number < 0) return Double.NaN;

            if (number == 0)
                return 0;

            double r = number;  // Initial guess for the square root
            double t = 1.0;    // Initial guess for the reciprocal of the square root

            // Normalize the initial guess for r
            while (r > 2.0)
            {
                r /= 4.0;
                t *= 2.0;
            }

            // Goldschmidt's iterations
            for (int i = 0; i < 5; i++) // Number of iterations can be adjusted for precision
            {
                t = t * (1.5 - 0.5 * r * t * t);
                r = r * (1.5 - 0.5 * r * t * t);
            }

            // Final adjustment as we normalized r in the beginning
            return number * t;
        }

        public static double SqrtGoldschmidt0(double number)
        {
            if (number < 0)
                return Double.NaN; // No square root for negative numbers

            if (number == 0 || number == 1)
                return number;

            double b = number; // Value to be square rooted
            double r = 1;     // Initial guess for the reciprocal of the square root
            double t;         // Temporary variable

            // Getting initial guess closer to the root
            while (b >= 2)
            {
                b /= 4;
                r *= 2;
            }

            // Goldschmidt's iterations
            for (int i = 0; i < 5; i++) // Iterations for convergence, adjust as necessary
            {
                t = b * r * r;
                r = r * (1.5 - t / 2);
                b = b * (1.5 - t / 2);
            }

            return number * r;
        }

        static public double SqrtNewtonRaphson(double number)
        {
            if (number < 0) return Double.NaN;
            if (number == 0 || number == 1) return number;

            double precision = 2*Double.Epsilon; // Precision of the approximation
            double estimate = number / 2.0; // Initial guess

            //int count = 0;

            while (true)
            {
                //count++;

                //double newEstimate = FusedMultiplyAdd(0.5, estimate, 0.5 * number / estimate);

                double newEstimate = 0.5 * (estimate + number / estimate);

                // Check if the absolute difference is within the desired precision
                if (Math.Abs(newEstimate - estimate) <= precision)
                {
                    return newEstimate;
                }

                estimate = newEstimate;
            }
        }

        static public double SqrtBinary(double x)
        {
            double baseValue = 128.0;
            double y = 0.0;

            // First, find the integer part
            for (int i = 1; i <= 15; i++)
            {
                y += baseValue;
                if ((y * y) > x)
                {
                    y -= baseValue; // Undo the last addition
                }
                baseValue /= 2.0; // Halve the baseValue
            }

            //return y;

            // Refine the result for floating-point precision
            double precision = 0.000000000000000000000001; // Precision of the result
            baseValue = 0.001; // Start with a tenth

            while (baseValue > precision)
            {
                y += baseValue;
                if ((y * y) > x)
                {
                    y -= baseValue; // Undo the last addition
                }
                baseValue /= 10.0; // Move to the next decimal place
            }

            return y;
        }

        public static double CordicSqrtn3(double S)
        {
            double x = S + 1.0;
            double y = S - 1.0;

            for (int i = 0; i < SQRTITERATIONS; i++)
            {
                double di = y >= 0 ? -1 : 1;

                // Correctly update x and y
                double xNew = x + di * y * pow2Table[i];
                double yNew = y - di * x * pow2Table[i];

                x = xNew;
                y = yNew;
            }

            return x;
        }


        public static double CordicSqrtn1(double value)
        {
            double x = value;
            double y = 0;
            double factor = 1;

            for (int i = 0; i < SQRTITERATIONS; i++)
            {
                double dx = (x > y) ? -1 : 1;
                double dy = (x > y) ? 1 : -1;

                double newX = x - dx * y * Math.Pow(2, -i);
                double newY = y + dy * x * Math.Pow(2, -i);
                x = newX;
                y = newY;

                x *= K_VALUES[i];
                y *= K_VALUES[i];

                if (i == 0)
                {
                    factor *= 0.5;
                }
                else
                {
                    factor *= K_VALUES[i];
                }
            }

            return x * factor;
        }

        /*
        
        public static double CordicSqrt(double S)
    {
        double x = 0.5;
        double y = 0.0;
        double z = S - 0.25;

        for (int i = 0; i < ITERATIONS; i++)
        {
            double di = (z >= 0) ? -1 : 1;
            double xShifted = x * pow2Table[i];
            double yShifted = y * pow2Table[i];

            // Rotation
            double xNew = x - di * yShifted;
            double yNew = y + di * xShifted;
            double zNew = z - di * arctanTable[i];

            x = xNew;
            y = yNew;
            z = zNew;
        }

        // Return the x value, which converges to the square root
        return x;
    }


         */

        static double[] CreateSineLookupTable(int step = 10)
        {
            int arraySize = 360 / step;
            double[] lookupTable = new double[arraySize];

            for (int i = 0; i < arraySize; i++)
            {
                double rad = i * step * Math.PI / 180;
                lookupTable[i] = Math.Sin(rad);
            }

            return lookupTable;
        }

        public static void CalculateSinCos(double angle, out double sin, out double cos)
        {

            // Reduce the angle to the range [-2π, 2π]
            angle %= 2 * Math.PI;

            // Map the angle to the first quadrant and record flips
            bool flipSin = false, flipCos = false;
            if (angle < 0)
            {
                angle = -angle; // Reflect to positive
                flipSin = true; // Sin is odd function
            }

            if (angle > Math.PI)
            {
                angle = 2 * Math.PI - angle; // Reflect from [π, 2π] to [0, π]
                flipSin = !flipSin;
            }

            if (angle > Math.PI / 2)
            {
                angle = Math.PI - angle; // Reflect from [π/2, π] to [0, π/2]
                flipCos = true;
            }

            double x = 1.0 / scaleFactors[angles.Length - 1]; // Initial vector length adjusted
            double y = 0.0;

            for (int i = 0; i < angles.Length - 1; i++)
            {
                double dx = (angle < 0) ? -y : y;
                double dy = (angle < 0) ? x : -x;
                int powerOfTwo = 1 << i;

                x += dx / powerOfTwo; //dx >> i; // Equivalent to dx / powerOfTwo
                y += dy / powerOfTwo; //dy >> i; // Equivalent to dy / powerOfTwo
                angle -= (angle < 0) ? -angles[i] : angles[i];
            }

            sin = flipSin ? -y : y;
            cos = flipCos ? -x : x;

            //sin = sin + (angle - sin) / 6; // Taylor series adjustment
            //cos = cos - (angle - cos) / 2; // Taylor series adjustment
        }

    

        public static double CalculateTan(double angle)
        {
            double sin, cos;
            CalculateSinCos(angle, out sin, out cos);

            // Implement a method to calculate tan using iterative approach without direct division
            // This part is complex and may need a separate algorithm for accuracy
            double tan = ComputeTanIteratively(sin, cos);

            return tan;
        }

        private const int ITERATIONS = 20;
        private static readonly double[] arctanValues = PreCalculateArctanValues(ITERATIONS);

        public static double CalculateLn(double number)
        {
            if (number <= 0)
            {
                //throw new ArgumentException("Number must be greater than zero.");
                return 0;
            }

            double x = 1.0;
            double y = 0.0;
            double z = number; // Initial z is set to the number
            double powerOfTwo = 0.5;

            for (int i = 0; i < ITERATIONS; i++)
            {
                double xNew, yNew;
                double arctanValue = arctanValues[i];

                if (z < 0)
                {
                    xNew = x - y * powerOfTwo;
                    yNew = y + x * powerOfTwo;
                    z += arctanValue;
                }
                else
                {
                    xNew = x + y * powerOfTwo;
                    yNew = y - x * powerOfTwo;
                    z -= arctanValue;
                }

                x = xNew;
                y = yNew;
                powerOfTwo /= 2.0;
            }

            return y;
        }

        private static double[] PreCalculateArctanValues(int iterations)
        {
            double[] values = new double[iterations];
            for (int i = 0; i < iterations; i++)
            {
                values[i] = Math.Atan(Math.Pow(2, -i));
            }
            return values;
        }



        private static double ComputeTanIteratively( double sin, double cos )
        {
            // Avoid division by checking if cos is near zero.
            // If cos is very small, tan tends to infinity.
            if ( Math.Abs(cos) < 1e-12 )
            {
                return sin >= 0 ? double.PositiveInfinity : double.NegativeInfinity;
            }

            // Compute the reciprocal of cos using Newton's method.
            // This iterative method approximates 1/cos without using the division operator.
            double recip = 1.0; // initial guess for 1/cos
            for ( int i = 0; i < 10; i++ )
            {
                recip = recip * (2.0 - cos * recip);
            }

            // The tangent is then computed as sin * (1/cos).
            return sin * recip;
        }

    }



}
